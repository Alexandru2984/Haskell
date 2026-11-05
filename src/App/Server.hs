{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
module App.Server where

import Control.Monad.IO.Class (liftIO)
import Network.Wai.Handler.Warp
    (runSettings, defaultSettings, setPort, setHost, setGracefulShutdownTimeout, setTimeout, setServerName)
import Data.String (fromString)
import Servant hiding (Summary, respond)
import Lucid (renderBS)
import Database.PostgreSQL.Simple
import Data.Pool (Pool, withResource)
import Data.Aeson (Value, eitherDecodeStrict, encode, object, (.=))
import Data.Bits (xor, (.|.))
import Data.List (foldl')
import Network.Wai (Middleware, pathInfo, responseFile)
import Network.Wai.Middleware.HttpAuth (basicAuth)
import Network.HTTP.Types (status200)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified System.Timeout
import App.Security.Web
import App.Security.UrlSafety (isSafeUrl)
import App.Contract (validateDefinition, validateContract)
import App.Config
import App.Db
import App.Migrations
import App.Routes
import App.Types
import App.Html
import App.Endpoint
import App.Reports
import App.Monitor
import App.Scheduler
import App.Logging

server :: AppConfig -> Pool Connection -> MonitorRuntime -> Server API
server cfg pool runtime =
         dashboardH
    :<|> liftIO (endpointsHtml <$> withResource pool getEndpoints)
    :<|> pure (endpointFormPage Nothing)
    :<|> editH
    :<|> createH
    :<|> updateH
    :<|> deleteH
    :<|> liftIO (incidentsHtml <$> withResource pool (\c -> recentIncidents c 50))
    :<|> healthH
    :<|> metricsH
    :<|> liftIO (withResource pool getEndpoints)
    :<|> detailH
    :<|> toggleH
    :<|> manualH
    :<|> exportH
    :<|> pure playgroundHtml
    :<|> validateH
  where
    dashboardH requested = do
        hours <- validatedWindow requested
        liftIO $ withResource pool $ \c ->
            dashboardHtml <$> getEndpoints c <*> summaryFor c Nothing hours <*> historyFor c Nothing hours 60 <*> recentIncidents c 3 <*> pure hours
    findEndpoint eid = do
        endpoint <- liftIO $ withResource pool (`getEndpointById` eid)
        maybe (htmlError err404 "Monitor not found" "This monitor does not exist or has been deleted.") pure endpoint
    editH eid = endpointFormPage . Just <$> findEndpoint eid
    createH form = do
        contract <- validateForm cfg form
        result <- liftIO $ withResource pool $ \c -> createEndpointLimited c (maxEndpoints cfg) (efName form) (efProject form) (efUrl form) (efMethod form) contract
        case result of
            Nothing -> htmlError err409 "Monitor limit reached" "Remove an unused monitor before adding another."
            Just eid -> redirectTo ("/endpoints/" ++ show eid)
    updateH eid form = do
        _ <- findEndpoint eid
        contract <- validateForm cfg form
        liftIO $ withResource pool $ \c -> updateEndpoint c eid (efName form) (efProject form) (efUrl form) (efMethod form) contract
        redirectTo ("/endpoints/" ++ show eid)
    deleteH eid = do
        _ <- findEndpoint eid
        liftIO $ withResource pool (`deleteEndpoint` eid)
        redirectTo "/endpoints"
    toggleH eid = do
        _ <- findEndpoint eid
        liftIO $ withResource pool (`toggleEndpoint` eid)
        redirectTo ("/endpoints/" ++ show eid)
    manualH eid = do
        endpoint <- findEndpoint eid
        if not (endpointEnabled endpoint) then htmlError err409 "Monitor is paused" "Resume this monitor before running a check." else pure ()
        allowed <- liftIO $ claimManualCheck runtime
        if not allowed then htmlError err429 "Please wait a moment" "Manual checks have a 5-second global cooldown. Try again shortly." else pure ()
        recorded <- liftIO $ runStoredCheck cfg pool runtime endpoint
        if not recorded then htmlError err409 "Check not recorded" "The monitor is already being checked, was changed, or was paused. Reload its details." else redirectTo ("/endpoints/" ++ show eid)
    detailH eid requested = do
        endpoint <- findEndpoint eid
        hours <- validatedWindow requested
        liftIO $ withResource pool $ \c -> endpointDetailHtml endpoint <$> summaryFor c (Just eid) hours <*> historyFor c (Just eid) hours 100 <*> pure hours
    exportH eid requested = do
        _ <- findEndpoint eid
        hours <- validatedWindow requested
        checks <- liftIO $ withResource pool $ \c -> historyFor c (Just eid) hours 1000
        pure $ addHeader ("attachment; filename=monitor-" ++ show eid ++ "-checks.csv") (checksCSV checks)
    healthH = liftIO $ withResource pool $ \c -> do
        [Only count] <- query_ c "SELECT count(*)::int FROM endpoints"
        (checks, _, _) <- globalStats c
        pure (Health "ok" count checks)
    metricsH = liftIO $ withResource pool $ \c -> do
        endpoints <- getEndpoints c
        summary <- summaryFor c Nothing 24
        pure (renderMetrics endpoints summary)
    validateH input = do
        if LBS.length (encode (inputContract input)) > 32768 || LBS.length (encode (inputResponse input)) > 65536
            then throwError err413 { errBody = "Contract limit is 32 KiB; response limit is 64 KiB" } else pure ()
        let definitionErrors = take 100 (validateDefinition (inputContract input))
            errors = if null definitionErrors then take 100 (validateContract (inputContract input) (inputResponse input)) else definitionErrors
        pure $ object ["valid" .= null errors, "errors" .= errors]

validatedWindow :: Maybe Int -> Handler Int
validatedWindow Nothing = pure 24
validatedWindow (Just hours) | hours `elem` [24,168,720] = pure hours
                            | otherwise = htmlError err400 "Unsupported period" "Choose 24 hours, 7 days, or 30 days."

validateForm :: AppConfig -> EndpointForm -> Handler Value
validateForm cfg form = do
    let validText value = not (T.null (T.strip value)) && T.length value <= 120 && not (T.any (\c -> c < ' ') value)
    if not (validText (efName form) && validText (efProject form)) then htmlError err400 "Invalid monitor details" "Name and project must contain 1 to 120 printable characters. Use your browser's Back button to correct the form." else pure ()
    if efMethod form `notElem` ["GET","HEAD"] then htmlError err400 "Unsupported method" "Monitoring supports read-only GET and HEAD requests." else pure ()
    if T.length (efContract form) > 32768 then htmlError err400 "Contract too large" "Contracts are limited to 32 KiB." else pure ()
    contract <- case eitherDecodeStrict (TE.encodeUtf8 (efContract form)) of
        Left _ -> htmlError err400 "Invalid JSON" "The contract could not be parsed as JSON. Use the playground to check it, or go back to correct the form."
        Right value | null (validateDefinition value) -> pure value
                    | otherwise -> htmlError err400 "Invalid contract" "A supported type and valid nested schemas are required. Test the contract in the playground for detailed errors."
    safe <- liftIO $ System.Timeout.timeout 3000000 (isSafeUrl (allowPrivateTargets cfg) (efUrl form))
    if safe /= Just True then htmlError err400 "Target URL refused" "Use a public IPv4-reachable HTTP(S) URL without credentials, spaces or fragments. Private and reserved addresses are blocked." else pure contract

htmlError :: ServerError -> T.Text -> T.Text -> Handler a
htmlError status title message = throwError status { errBody = renderBS (errorHtml title message), errHeaders = [("Content-Type","text/html; charset=utf-8")] }
redirectTo :: String -> Handler Redirect
redirectTo location = pure (addHeader location NoContent)

checksCSV :: [CheckResult] -> T.Text
checksCSV checks = T.unlines ("time_utc,http_status,latency_ms,passed,errors" : map row checks)
  where
    row c = T.intercalate "," [cell (T.pack (show (checkTime c))), T.pack (show (checkStatus c)), T.pack (show (checkLatencyMs c)), if checkPassed c then "true" else "false", cell (valueToText (checkErrors c))]
    -- Quotes protect delimiters; apostrophes prevent spreadsheet formula execution.
    cell value = "\"" <> T.replace "\"" "\"\"" (if T.any (`elem` ("=+-@\t\r\n" :: String)) (T.take 1 (T.stripStart value)) then "'" <> value else value) <> "\""

renderMetrics :: [Endpoint] -> Summary -> T.Text
renderMetrics endpoints summary = T.unlines
    [ "# HELP api_monitor_endpoints Configured endpoints.", "# TYPE api_monitor_endpoints gauge"
    , "api_monitor_endpoints " <> text (length endpoints)
    , "# TYPE api_monitor_endpoints_healthy gauge"
    , "api_monitor_endpoints_healthy " <> text (length (filter (\e -> endpointEnabled e && endpointStatus e == Passing) endpoints))
    , "# TYPE api_monitor_checks_24h gauge", "api_monitor_checks_24h " <> text (summaryTotal summary)
    , "# TYPE api_monitor_checks_passed_24h gauge", "api_monitor_checks_passed_24h " <> text (summaryPassed summary)
    , "# TYPE api_monitor_latency_avg_ms gauge", "api_monitor_latency_avg_ms " <> maybe "0" text (summaryAverage summary)
    , "# TYPE api_monitor_latency_p95_ms gauge", "api_monitor_latency_p95_ms " <> maybe "0" text (summaryP95 summary) ]

app :: AppConfig -> Pool Connection -> MonitorRuntime -> Application
app cfg pool runtime = securityHeaders $ authMiddleware cfg $ protectWrites cfg $ assets $ serve api (server cfg pool runtime)

assets :: Middleware
assets application request respond = case pathInfo request of
    ["assets", "app.css"] -> file "text/css; charset=utf-8" "public/assets/app.css"
    ["assets", "app.js"] -> file "text/javascript; charset=utf-8" "public/assets/app.js"
    ["assets", "favicon.svg"] -> file "image/svg+xml" "public/assets/favicon.svg"
    _ -> application request respond
  where file mime path = respond $ responseFile status200 [("Content-Type",mime)] path Nothing

authMiddleware :: AppConfig -> Middleware
authMiddleware cfg | basicAuthEnabled cfg = basicAuth checkCreds "Haskell Pulse"
                   | otherwise = id
  where
    checkCreds user pass = pure (constEq user (TE.encodeUtf8 (T.pack (basicAuthUser cfg))) && constEq pass (TE.encodeUtf8 (T.pack (basicAuthPass cfg))))

constEq :: BS.ByteString -> BS.ByteString -> Bool
constEq a b = BS.length a == BS.length b && 0 == foldl' (\acc (x,y) -> acc .|. xor x y) 0 (BS.zip a b)

runServer :: IO ()
runServer = do
    logInfo "Starting Haskell Pulse..."
    cfg <- loadConfig
    pool <- mkPool cfg
    withResource pool runMigrations
    runtime <- newMonitorRuntime cfg
    startScheduler cfg pool runtime
    let settings = setPort (appPort cfg) $ setHost (fromString (appHost cfg))
                 $ setServerName "Haskell Pulse" $ setTimeout 30
                 $ setGracefulShutdownTimeout (Just 10) defaultSettings
    logInfo $ "Listening on " ++ appHost cfg ++ ":" ++ show (appPort cfg)
    runSettings settings (app cfg pool runtime)

{-# LANGUAGE OverloadedStrings #-}
module App.Server where

import qualified System.Timeout
import Control.Monad.IO.Class (liftIO)
import Network.Wai.Handler.Warp
    (runSettings, defaultSettings, setPort, setHost, setGracefulShutdownTimeout)
import Data.String (fromString)
import Servant
import Lucid (Html)
import Database.PostgreSQL.Simple
import Data.Pool (Pool, withResource)
import Data.Aeson (Value, eitherDecodeStrict)
import Data.Bits (xor, (.|.))
import Data.List (foldl')
import Network.Wai (Middleware)
import Network.Wai.Middleware.HttpAuth (basicAuth)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BC
import App.Security.Web
import App.Security.UrlSafety (isSafeUrl)
import App.Contract (validateDefinition)
import App.Config
import App.Db
import App.Migrations
import App.Routes
import App.Types (Endpoint(..), Health(..), Status(..))
import App.Html
import App.Endpoint
import App.Reports (globalStats, recentIncidents)
import App.Monitor (newMonitorRuntime)
import App.Scheduler
import App.Logging

server :: AppConfig -> Pool Connection -> Server API
server cfg pool =
         liftIO dashboardH
    :<|> liftIO (endpointsHtml <$> withResource pool getEndpoints)
    :<|> return (endpointFormPage Nothing)
    :<|> editH pool
    :<|> createH cfg pool
    :<|> updateH cfg pool
    :<|> deleteH pool
    :<|> liftIO incidentsH
    :<|> liftIO healthH
    :<|> liftIO metricsH
    :<|> liftIO (withResource pool getEndpoints)
  where
    dashboardH = withResource pool $ \c ->
        dashboardHtml <$> getEndpoints c <*> globalStats c
    incidentsH = withResource pool $ \c ->
        incidentsHtml <$> recentIncidents c 50
    healthH = withResource pool $ \c -> do
        eps <- getEndpoints c
        (checks, _, _) <- globalStats c
        return (Health "ok" (length eps) checks)
    metricsH = withResource pool $ \c -> do
        eps <- getEndpoints c
        (checks, passed, avg) <- globalStats c
        let healthy = length (filter (\e -> endpointStatus e == Passing) eps)
            failing = length (filter (\e -> endpointStatus e == Failing) eps)
        return (renderMetrics (length eps) healthy failing checks passed avg)

renderMetrics :: Int -> Int -> Int -> Int -> Int -> Maybe Double -> T.Text
renderMetrics total healthy failing checks passed avg = T.unlines
    [ "# HELP api_monitor_endpoints_total Number of configured endpoints."
    , "# TYPE api_monitor_endpoints_total gauge"
    , "api_monitor_endpoints_total "   <> tshow total
    , "api_monitor_endpoints_healthy " <> tshow healthy
    , "api_monitor_endpoints_failing " <> tshow failing
    , "# HELP api_monitor_checks_total Total checks recorded."
    , "# TYPE api_monitor_checks_total counter"
    , "api_monitor_checks_total "  <> tshow checks
    , "api_monitor_checks_passed " <> tshow passed
    , "api_monitor_check_latency_avg_ms " <> maybe "0" (tshow . (round :: Double -> Int)) avg
    ]
  where
    tshow :: Show a => a -> T.Text
    tshow = T.pack . show

editH :: Pool Connection -> Int -> Handler (Html ())
editH pool eid = do
    mep <- liftIO $ withResource pool (`getEndpointById` eid)
    maybe (throwError err404) (return . endpointFormPage . Just) mep

createH :: AppConfig -> Pool Connection -> EndpointForm -> Handler Redirect
createH cfg pool form = do
    validateForm cfg form
    contract <- parseContractOrErr (efContract form)
    _ <- liftIO $ withResource pool $ \c ->
        createEndpoint c (efName form) (efProject form) (efUrl form) (efMethod form) contract
    redirectTo "/endpoints"

updateH :: AppConfig -> Pool Connection -> Int -> EndpointForm -> Handler Redirect
updateH cfg pool eid form = do
    validateForm cfg form
    contract <- parseContractOrErr (efContract form)
    liftIO $ withResource pool $ \c ->
        updateEndpoint c eid (efName form) (efProject form) (efUrl form) (efMethod form) contract
    redirectTo "/endpoints"

deleteH :: Pool Connection -> Int -> Handler Redirect
deleteH pool eid = do
    liftIO $ withResource pool (`deleteEndpoint` eid)
    redirectTo "/endpoints"

redirectTo :: String -> Handler Redirect
redirectTo loc = return (addHeader loc NoContent)

parseContractOrErr :: T.Text -> Handler Value
parseContractOrErr txt =
    case eitherDecodeStrict (TE.encodeUtf8 txt) of
        Right v | null (validateDefinition v) -> return v
                | otherwise -> throwError err400 { errBody = "Invalid contract definition: a supported type and valid nested schemas are required" }
        Left _  -> throwError err400 { errBody = "Invalid contract JSON" }

app :: AppConfig -> Pool Connection -> Application
app cfg pool = securityHeaders $ authMiddleware cfg $ protectWrites cfg $ serve api (server cfg pool)

-- | Gate the whole app behind HTTP Basic auth when enabled in config.
authMiddleware :: AppConfig -> Middleware
authMiddleware cfg
    | basicAuthEnabled cfg = basicAuth checkCreds "API Monitor"
    | otherwise            = id
  where
    expectedUser = BC.pack (basicAuthUser cfg)
    expectedPass = BC.pack (basicAuthPass cfg)
    checkCreds u p = return (constEq u expectedUser && constEq p expectedPass)

-- | Constant-time bytestring equality to avoid leaking length-prefix matches
-- via response timing.
constEq :: BS.ByteString -> BS.ByteString -> Bool
constEq a b =
    BS.length a == BS.length b
    && 0 == foldl' (\acc (x, y) -> acc .|. xor x y) 0 (BS.zip a b)

runServer :: IO ()
runServer = do
    logInfo "Starting application..."
    cfg <- loadConfig
    pool <- mkPool cfg
    withResource pool runMigrations

    runtime <- newMonitorRuntime cfg
    startScheduler cfg pool runtime

    let settings = setPort (appPort cfg)
                 $ setHost (fromString (appHost cfg))
                 $ setGracefulShutdownTimeout (Just 10) defaultSettings
    logInfo $ "Listening on " ++ appHost cfg ++ ":" ++ show (appPort cfg)

    runSettings settings (app cfg pool)

validateForm :: AppConfig -> EndpointForm -> Handler ()
validateForm cfg form = do
    let validText value limit = not (T.null (T.strip value)) && T.length value <= limit && not (T.any (\c -> c < ' ') value)
    if not (validText (efName form) 120 && validText (efProject form) 120)
        then throwError err400 { errBody = "Name and project must contain 1 to 120 printable characters" } else pure ()
    if efMethod form `notElem` ["GET", "HEAD"]
        then throwError err400 { errBody = "Monitoring supports read-only GET and HEAD requests" } else pure ()
    if T.length (efContract form) > 32768
        then throwError err400 { errBody = "Contract is too large (maximum 32 KiB)" } else pure ()
    safe <- liftIO $ System.Timeout.timeout 3000000 (isSafeUrl (allowPrivateTargets cfg) (efUrl form))
    if safe /= Just True then throwError err400 { errBody = "Target must resolve to public IPv4 addresses; private, reserved and invalid URLs are refused" } else pure ()

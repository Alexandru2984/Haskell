{-# LANGUAGE OverloadedStrings #-}
module App.Server where

import Control.Monad (void)
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
import qualified Data.ByteString.Lazy.Char8 as LBS
import App.Config
import App.Db
import App.Migrations
import App.Routes
import App.Types (Endpoint(..), Health(..), Status(..))
import App.Html
import App.Endpoint
import App.Reports (globalStats, recentIncidents)
import App.Scheduler
import App.Logging

server :: Pool Connection -> Server API
server pool =
         liftIO dashboardH
    :<|> liftIO (endpointsHtml <$> withResource pool getEndpoints)
    :<|> return (endpointFormPage Nothing)
    :<|> editH pool
    :<|> createH pool
    :<|> updateH pool
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

createH :: Pool Connection -> EndpointForm -> Handler Redirect
createH pool form = do
    contract <- parseContractOrErr (efContract form)
    _ <- liftIO $ withResource pool $ \c ->
        createEndpoint c (efName form) (efProject form) (efUrl form) (efMethod form) contract
    redirectTo "/endpoints"

updateH :: Pool Connection -> Int -> EndpointForm -> Handler Redirect
updateH pool eid form = do
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
        Right v -> return v
        Left e  -> throwError err400 { errBody = LBS.pack ("Invalid contract JSON: " ++ e) }

app :: AppConfig -> Pool Connection -> Application
app cfg pool = authMiddleware cfg (serve api (server pool))

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

    -- Insert a sample if the db is empty just to show UI
    count <- withResource pool $ \conn -> do
        [Only c] <- query_ conn "SELECT COUNT(*) FROM endpoints" :: IO [Only Int]
        return c
    if count == 0
        then do
            logInfo "Inserting sample data..."
            withResource pool insertSample
        else return ()

    startScheduler cfg pool

    let settings = setPort (appPort cfg)
                 $ setHost (fromString (appHost cfg))
                 $ setGracefulShutdownTimeout (Just 10) defaultSettings
    logInfo $ "Listening on " ++ appHost cfg ++ ":" ++ show (appPort cfg)

    runSettings settings (app cfg pool)

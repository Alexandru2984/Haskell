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
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString.Lazy.Char8 as LBS
import App.Config
import App.Db
import App.Migrations
import App.Routes
import App.Html
import App.Endpoint
import App.Scheduler
import App.Logging

server :: Pool Connection -> Server API
server pool =
         liftIO (dashboardHtml <$> withResource pool getEndpoints)
    :<|> liftIO (endpointsHtml <$> withResource pool getEndpoints)
    :<|> return (endpointFormPage Nothing)
    :<|> editH pool
    :<|> createH pool
    :<|> updateH pool
    :<|> deleteH pool
    :<|> liftIO (withResource pool getEndpoints)

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

app :: Pool Connection -> Application
app pool = serve api (server pool)

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

    runSettings settings (app pool)

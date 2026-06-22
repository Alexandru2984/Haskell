{-# LANGUAGE OverloadedStrings #-}
module App.Server where

import Control.Monad.IO.Class (liftIO)
import Network.Wai.Handler.Warp (run)
import Servant
import Database.PostgreSQL.Simple
import Data.Pool (Pool, withResource)
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
    :<|> liftIO (withResource pool getEndpoints)

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

    let port = appPort cfg
    logInfo $ "Listening on port " ++ show port

    run port (app pool)

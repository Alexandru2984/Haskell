{-# LANGUAGE OverloadedStrings #-}
module App.Server where

import Control.Monad.IO.Class (liftIO)
import Network.Wai.Handler.Warp (run)
import Servant
import Database.PostgreSQL.Simple
import App.Config
import App.Db
import App.Migrations
import App.Routes
import App.Html
import App.Endpoint
import App.Scheduler
import App.Logging

server :: Connection -> Server API
server conn = 
    (return $ dashboardHtml [])
    :<|> (liftIO $ getEndpoints conn)

app :: Connection -> Application
app conn = serve api (server conn)

runServer :: IO ()
runServer = do
    logInfo "Starting application..."
    cfg <- loadConfig
    conn <- connectDb cfg
    runMigrations conn
    startScheduler cfg conn
    
    let port = appPort cfg
    logInfo $ "Listening on port " ++ show port
    
    run port (app conn)

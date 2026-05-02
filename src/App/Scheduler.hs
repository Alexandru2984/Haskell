{-# LANGUAGE OverloadedStrings #-}
module App.Scheduler where

import Control.Concurrent (threadDelay, forkIO)
import Control.Monad (forever, void)
import Database.PostgreSQL.Simple
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import App.Types
import App.Checker
import App.Config
import App.Logging

startScheduler :: AppConfig -> Connection -> IO ()
startScheduler cfg conn = void $ forkIO $ do
    manager <- newManager tlsManagerSettings
    forever $ do
        logInfo "Scheduler tick..."
        -- Simplified: just sleep for now
        threadDelay $ 60 * 1000000 -- 1 minute

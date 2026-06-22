{-# LANGUAGE OverloadedStrings #-}
module App.Scheduler where

import Control.Concurrent (threadDelay, forkIO)
import Control.Monad (forever, void)
import Database.PostgreSQL.Simple (Connection)
import Data.Pool (Pool)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import App.Types
import App.Checker
import App.Config
import App.Logging

startScheduler :: AppConfig -> Pool Connection -> IO ()
startScheduler cfg pool = void $ forkIO $ do
    manager <- newManager tlsManagerSettings
    forever $ do
        logInfo "Scheduler tick..."
        -- Simplified: just sleep for now
        threadDelay $ 60 * 1000000 -- 1 minute

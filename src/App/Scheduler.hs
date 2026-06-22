{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module App.Scheduler where

import Control.Concurrent (threadDelay, forkIO)
import Control.Concurrent.QSem (QSem, newQSem, waitQSem, signalQSem)
import Control.Concurrent.Async (forConcurrently_)
import Control.Exception (bracket_, try, SomeException)
import Control.Monad (forever, void)
import Database.PostgreSQL.Simple (Connection)
import Data.Pool (Pool, withResource)
import Network.HTTP.Client (Manager, newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import App.Types
import App.Checker (checkEndpoint)
import App.Endpoint (getEnabledEndpoints, setEndpointStatus)
import App.Reports (insertCheckResult)
import App.Config
import App.Logging

-- | Background loop: every @checkIntervalSeconds@ it fetches all enabled
-- endpoints and checks them concurrently (bounded by @maxConcurrentChecks@),
-- persisting each result and updating the endpoint's health.
startScheduler :: AppConfig -> Pool Connection -> IO ()
startScheduler cfg pool = void $ forkIO $ do
    manager <- newManager tlsManagerSettings
    forever $ do
        endpoints <- withResource pool getEnabledEndpoints
        logInfo $ "Scheduler tick: checking " ++ show (length endpoints) ++ " endpoint(s)"
        sem <- newQSem (maxConcurrentChecks cfg)
        forConcurrently_ endpoints (runOne cfg manager pool sem)
        threadDelay (checkIntervalSeconds cfg * 1000000)

runOne :: AppConfig -> Manager -> Pool Connection -> QSem -> Endpoint -> IO ()
runOne cfg manager pool sem ep =
    bracket_ (waitQSem sem) (signalQSem sem) $ do
        result <- try $ do
            cr <- checkEndpoint cfg manager ep
            withResource pool $ \conn -> do
                insertCheckResult conn cr
                setEndpointStatus conn (endpointId ep)
                    (if checkPassed cr then Passing else Failing)
        case result of
            Left (e :: SomeException) ->
                logError $ "Check failed for endpoint "
                            ++ show (endpointId ep) ++ ": " ++ show e
            Right () -> return ()

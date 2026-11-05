{-# LANGUAGE ScopedTypeVariables #-}
module App.Scheduler where

import Control.Concurrent (threadDelay, forkIO)
import Control.Concurrent.Async (replicateConcurrently_)
import Control.Exception (try, SomeException, SomeAsyncException, fromException, throwIO)
import Control.Monad (forever, void, when)
import Data.IORef
import Data.Pool (Pool, withResource)
import Database.PostgreSQL.Simple (Connection)
import App.Config
import App.Endpoint (getEnabledEndpoints)
import App.Monitor
import App.Reports (pruneHistory)
import App.Logging

-- Catch ordinary failures, never cancellation or timeout exceptions.
trySync :: IO a -> IO (Either SomeException a)
trySync action = do
    result <- try action
    case result of
        Left e | Just (_ :: SomeAsyncException) <- fromException e -> throwIO e
        _ -> pure result

startScheduler :: AppConfig -> Pool Connection -> MonitorRuntime -> IO ()
startScheduler cfg pool runtime = void $ forkIO $ do
    ticks <- newIORef (0 :: Int)
    forever $ do
        result <- trySync $ do
            endpoints <- withResource pool getEnabledEndpoints
            queue <- newIORef endpoints
            let worker = do
                    next <- atomicModifyIORef' queue $ \xs -> case xs of
                        [] -> ([], Nothing)
                        e:rest -> (rest, Just e)
                    case next of
                        Nothing -> pure ()
                        Just endpoint -> do
                            outcome <- trySync (runStoredCheck cfg pool runtime endpoint)
                            case outcome of
                                Left _ -> logError "Endpoint check could not be persisted; scheduler will retry next tick"
                                Right _ -> pure ()
                            worker
            replicateConcurrently_ (maxConcurrentChecks cfg) worker
            tick <- atomicModifyIORef' ticks (\n -> (n+1,n))
            when (retentionDays cfg > 0 && tick `mod` 240 == 0) $
                withResource pool (\conn -> pruneHistory conn (retentionDays cfg))
        case result of
            Left _ -> logError "Scheduler tick failed; retrying after the configured interval"
            Right () -> pure ()
        threadDelay (checkIntervalSeconds cfg * 1000000)

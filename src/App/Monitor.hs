{-# LANGUAGE OverloadedStrings #-}
module App.Monitor where

import Control.Concurrent.QSem
import Control.Exception (bracket_, finally)
import Data.IORef
import qualified Data.Set as Set
import Data.Time (UTCTime, getCurrentTime, diffUTCTime)
import Data.Pool (Pool, withResource)
import Database.PostgreSQL.Simple
import Network.HTTP.Client (Manager, newManager, managerSetProxy, noProxy, managerSetMaxHeaderLength, managerSetMaxNumberHeaders)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import App.Config
import App.Types
import App.Checker (checkEndpoint)
import App.Endpoint (endpointColumns, setEndpointStatus)
import App.Reports (insertCheckResult)

data MonitorRuntime = MonitorRuntime
    { monitorManager :: Manager, monitorSlots :: QSem
    , monitorActive :: IORef (Set.Set Int), manualLastRun :: IORef (Maybe UTCTime) }

newMonitorRuntime :: AppConfig -> IO MonitorRuntime
newMonitorRuntime cfg = MonitorRuntime
    <$> newManager (managerSetProxy noProxy (managerSetMaxHeaderLength 16384 (managerSetMaxNumberHeaders 64 tlsManagerSettings)))
    <*> newQSem (maxConcurrentChecks cfg) <*> newIORef Set.empty <*> newIORef Nothing

-- A global cooldown plus the shared slot bound prevents manual-check fanout.
claimManualCheck :: MonitorRuntime -> IO Bool
claimManualCheck runtime = do
    now <- getCurrentTime
    atomicModifyIORef' (manualLastRun runtime) $ \previous ->
        if maybe False (\t -> diffUTCTime now t < 5) previous
        then (previous, False) else (Just now, True)

runStoredCheck :: AppConfig -> Pool Connection -> MonitorRuntime -> Endpoint -> IO Bool
runStoredCheck cfg pool runtime endpoint = do
    claimed <- atomicModifyIORef' (monitorActive runtime) $ \active ->
        if Set.member eid active then (active,False) else (Set.insert eid active,True)
    if not claimed then pure False else
        (bracket_ (waitQSem (monitorSlots runtime)) (signalQSem (monitorSlots runtime)) $ do
            result <- checkEndpoint cfg (monitorManager runtime) endpoint
            withResource pool $ \conn -> withTransaction conn $ do
                -- Lock the definition before recording. A deleted/edited/paused monitor
                -- must not inherit a stale check that started against its previous settings.
                current <- query conn ("SELECT " <> endpointColumns <> " FROM endpoints WHERE id = ? FOR UPDATE") (Only eid)
                case current of
                    [e] | endpointEnabled e && endpointUrl e == endpointUrl endpoint
                        && endpointRevision e == endpointRevision endpoint
                        && endpointMethod e == endpointMethod endpoint && endpointContract e == endpointContract endpoint -> do
                            insertCheckResult conn result
                            setEndpointStatus conn eid (if checkPassed result then Passing else Failing)
                            pure True
                    _ -> pure False)
        `finally` atomicModifyIORef' (monitorActive runtime) (\active -> (Set.delete eid active, ()))
  where eid = endpointId endpoint

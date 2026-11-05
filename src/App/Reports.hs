{-# LANGUAGE OverloadedStrings #-}
module App.Reports where

import Control.Monad (void)
import Data.Time (UTCTime)
import Data.Aeson (Value)
import qualified Data.Text as T
import Database.PostgreSQL.Simple
import App.Types

-- | Persist the outcome of a single check.
insertCheckResult :: Connection -> CheckResult -> IO ()
insertCheckResult conn cr = void $ execute conn
    "INSERT INTO check_results (endpoint_id, check_time, status, latency_ms, passed, errors) \
    \ VALUES (?, ?, ?, ?, ?, ?)"
    ( checkEndpointId cr, checkTime cr, checkStatus cr, checkLatencyMs cr
    , checkPassed cr, checkErrors cr )

-- | The most recent check results across all endpoints.
recentChecks :: Connection -> Int -> IO [CheckResult]
recentChecks conn lim = query conn
    "SELECT id, endpoint_id, check_time, status, latency_ms, passed, errors \
    \ FROM check_results ORDER BY check_time DESC LIMIT ?"
    (Only lim)

-- | name, url, status, latency_ms, time, errors for recent failing checks.
recentIncidents :: Connection -> Int -> IO [(T.Text, T.Text, Int, Int, UTCTime, Value)]
recentIncidents conn lim = query conn
    "SELECT e.name, e.url, c.status, c.latency_ms, c.check_time, c.errors \
    \ FROM check_results c JOIN endpoints e ON e.id = c.endpoint_id \
    \ WHERE c.passed = false ORDER BY c.check_time DESC LIMIT ?"
    (Only lim)

-- | (total checks, passed checks, average latency) for one endpoint.
uptimeFor :: Connection -> Int -> IO (Int, Int, Maybe Double)
uptimeFor conn eid = do
    rows <- query conn
        "SELECT count(*)::int, \
        \       count(*) FILTER (WHERE passed)::int, \
        \       avg(latency_ms)::float8 \
        \ FROM check_results WHERE endpoint_id = ?"
        (Only eid)
    return $ case rows of
        (r : _) -> r
        []      -> (0, 0, Nothing)

-- | Global counters used by /metrics and the dashboard.
globalStats :: Connection -> IO (Int, Int, Maybe Double)
globalStats conn = do
    rows <- query_ conn
        "SELECT count(*)::int, \
        \       count(*) FILTER (WHERE passed)::int, \
        \       avg(latency_ms)::float8 \
        \ FROM check_results WHERE check_time >= now() - interval '24 hours'"
    return $ case rows of
        (r : _) -> r
        []      -> (0, 0, Nothing)


-- Windowed queries use indexes and fixed bounded output sizes.
summaryFor :: Connection -> Maybe Int -> Int -> IO Summary
summaryFor conn endpoint hours = do
    rows <- case endpoint of
        Nothing -> query conn
            "SELECT count(*)::int, count(*) FILTER (WHERE passed)::int, avg(latency_ms)::float8, percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)::float8 FROM check_results WHERE check_time >= now() - (? * interval '1 hour')"
            (Only hours)
        Just eid -> query conn
            "SELECT count(*)::int, count(*) FILTER (WHERE passed)::int, avg(latency_ms)::float8, percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)::float8 FROM check_results WHERE endpoint_id = ? AND check_time >= now() - (? * interval '1 hour')"
            (eid,hours)
    pure $ case rows of
        row:_ -> row
        [] -> Summary 0 0 Nothing Nothing

historyFor :: Connection -> Maybe Int -> Int -> Int -> IO [CheckResult]
historyFor conn endpoint hours limit = case endpoint of
    Nothing -> query conn
        "SELECT id, endpoint_id, check_time, status, latency_ms, passed, errors FROM check_results WHERE check_time >= now() - (? * interval '1 hour') ORDER BY check_time DESC, id DESC LIMIT ?"
        (hours, min 1000 (max 1 limit))
    Just eid -> query conn
        "SELECT id, endpoint_id, check_time, status, latency_ms, passed, errors FROM check_results WHERE endpoint_id = ? AND check_time >= now() - (? * interval '1 hour') ORDER BY check_time DESC, id DESC LIMIT ?"
        (eid, hours, min 1000 (max 1 limit))

pruneHistory :: Connection -> Int -> IO ()
pruneHistory conn days = void $ execute conn
    "DELETE FROM check_results WHERE check_time < now() - (? * interval '1 day')" (Only days)

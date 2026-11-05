{-# LANGUAGE OverloadedStrings #-}
module App.Migrations where

import Database.PostgreSQL.Simple
import App.Logging (logInfo)

runMigrations :: Connection -> IO ()
runMigrations conn = withTransaction conn $ do
    logInfo "Running migrations..."
    _ <- execute_ conn "CREATE TABLE IF NOT EXISTS endpoints ( \
        \ id SERIAL PRIMARY KEY, \
        \ name VARCHAR(255) NOT NULL, \
        \ project VARCHAR(255) NOT NULL, \
        \ url TEXT NOT NULL, \
        \ method VARCHAR(10) NOT NULL, \
        \ status INT NOT NULL DEFAULT 0, \
        \ enabled BOOLEAN NOT NULL DEFAULT true, \
        \ contract JSONB NOT NULL \
        \ )"
    _ <- execute_ conn "CREATE TABLE IF NOT EXISTS check_results ( \
        \ id SERIAL PRIMARY KEY, \
        \ endpoint_id INT REFERENCES endpoints(id) ON DELETE CASCADE, \
        \ check_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, \
        \ status INT NOT NULL, \
        \ latency_ms INT NOT NULL, \
        \ passed BOOLEAN NOT NULL, \
        \ errors JSONB NOT NULL \
        \ )"
    _ <- execute_ conn "ALTER TABLE endpoints ADD COLUMN IF NOT EXISTS revision INT NOT NULL DEFAULT 0"
    _ <- execute_ conn "CREATE INDEX IF NOT EXISTS check_results_time_idx ON check_results (check_time DESC, id DESC)"
    _ <- execute_ conn "CREATE INDEX IF NOT EXISTS check_results_endpoint_time_idx ON check_results (endpoint_id, check_time DESC, id DESC)"
    _ <- execute_ conn "CREATE INDEX IF NOT EXISTS check_results_failures_idx ON check_results (check_time DESC) WHERE passed = false"
    logInfo "Migrations complete."

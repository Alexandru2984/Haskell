{-# LANGUAGE OverloadedStrings #-}
module App.Migrations where

import Database.PostgreSQL.Simple
import App.Logging (logInfo)

runMigrations :: Connection -> IO ()
runMigrations conn = do
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
    logInfo "Migrations complete."

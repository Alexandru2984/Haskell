{-# LANGUAGE OverloadedStrings #-}
module App.Endpoint where

import Database.PostgreSQL.Simple
import App.Types
import Data.Aeson (Value)

-- Re-declare to match our DB schema if needed. 
-- Schema from Migrations.hs: id, name, project, url, method, status, enabled, contract
getEndpoints :: Connection -> IO [Endpoint]
getEndpoints conn = do
    -- Using query_ because we just select everything
    query_ conn "SELECT id, name, project, url, method, status, enabled, contract FROM endpoints ORDER BY id DESC"

insertSample :: Connection -> IO ()
insertSample conn = do
    let contractStr = "{\"type\": \"object\", \"required\": {\"status\": {\"type\": \"string\"}}, \"allow_extra_fields\": true}" :: String
    _ <- execute conn "INSERT INTO endpoints (name, project, url, method, status, enabled, contract) VALUES (?, ?, ?, ?, ?, ?, ?)"
        ("Sample API" :: String, "Demo" :: String, "https://haskell.micutu.com" :: String, "GET" :: String, 1 :: Int, True :: Bool, contractStr)
    return ()
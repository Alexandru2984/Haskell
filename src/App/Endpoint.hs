{-# LANGUAGE OverloadedStrings #-}
module App.Endpoint where

import Database.PostgreSQL.Simple
import App.Types

-- Stub for DB operations
getEndpoints :: Connection -> IO [Endpoint]
getEndpoints conn = return []

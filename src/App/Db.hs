{-# LANGUAGE OverloadedStrings #-}
module App.Db where

import Database.PostgreSQL.Simple (Connection, connectPostgreSQL, close)
import Data.Pool (Pool, newPool, defaultPoolConfig)
import App.Config (AppConfig(..))
import qualified Data.ByteString.Char8 as B

-- | A pool of PostgreSQL connections. A single 'Connection' is not safe for
-- concurrent use across Warp's request threads, so every handler borrows a
-- connection from the pool for the duration of its work.
mkPool :: AppConfig -> IO (Pool Connection)
mkPool cfg =
    newPool $ defaultPoolConfig
        (connectPostgreSQL (B.pack (dbUrl cfg))) -- create
        close                                    -- destroy
        60.0                                     -- keep idle connections 60s
        10                                       -- max connections in the pool

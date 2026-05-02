{-# LANGUAGE OverloadedStrings #-}
module App.Db where

import Database.PostgreSQL.Simple
import App.Config (AppConfig(..))
import qualified Data.ByteString.Char8 as B

connectDb :: AppConfig -> IO Connection
connectDb cfg = connectPostgreSQL (B.pack $ dbUrl cfg)

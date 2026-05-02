{-# LANGUAGE OverloadedStrings #-}
module App.Config where

import System.Environment (lookupEnv)
import Data.Maybe (fromMaybe)
import Text.Read (readMaybe)
import Configuration.Dotenv (loadFile, defaultConfig)

data AppConfig = AppConfig
    { appPort :: Int
    , dbUrl :: String
    , allowPrivateTargets :: Bool
    } deriving (Show)

loadConfig :: IO AppConfig
loadConfig = do
    _ <- loadFile defaultConfig
    portStr <- fromMaybe "3060" <$> lookupEnv "APP_PORT"
    db <- fromMaybe "postgresql://haskell_monitor_user:change_me@127.0.0.1:5432/haskell_monitor" <$> lookupEnv "DATABASE_URL"
    privateTargetsStr <- fromMaybe "false" <$> lookupEnv "ALLOW_PRIVATE_TARGETS"
    
    let port = fromMaybe 3060 (readMaybe portStr)
        privateTargets = privateTargetsStr == "true"
        
    return $ AppConfig port db privateTargets
{-# LANGUAGE OverloadedStrings #-}
module App.Config where

import System.Environment (lookupEnv)
import Data.Maybe (fromMaybe)
import Text.Read (readMaybe)
import Configuration.Dotenv (loadFile, defaultConfig)

data AppConfig = AppConfig
    { appPort              :: Int
    , appHost              :: String
    , dbUrl                :: String
    , allowPrivateTargets  :: Bool
    , maxResponseBytes     :: Int
    , timeoutSeconds       :: Int
    , checkIntervalSeconds :: Int
    , maxConcurrentChecks  :: Int
    , basicAuthEnabled     :: Bool
    , basicAuthUser        :: String
    , basicAuthPass        :: String
    } deriving (Show)

loadConfig :: IO AppConfig
loadConfig = do
    _ <- loadFile defaultConfig
    port            <- envInt  "APP_PORT" 3060
    host            <- envStr  "APP_HOST" "127.0.0.1"
    db              <- envStr  "DATABASE_URL"
                         "postgresql://haskell_monitor_user:change_me@127.0.0.1:5432/haskell_monitor"
    privateTargets  <- envBool "ALLOW_PRIVATE_TARGETS" False
    maxBytes        <- envInt  "MAX_RESPONSE_BYTES" (1024 * 1024)
    timeoutS        <- envInt  "DEFAULT_TIMEOUT_SECONDS" 10
    intervalS       <- envInt  "DEFAULT_CHECK_INTERVAL_SECONDS" 60
    concurrency     <- envInt  "MAX_CONCURRENT_CHECKS" 4
    authEnabled     <- envBool "APP_BASIC_AUTH_ENABLED" False
    authUser        <- envStr  "APP_USERNAME" ""
    authPass        <- envStr  "APP_PASSWORD" ""

    return $ AppConfig
        { appPort              = port
        , appHost              = host
        , dbUrl                = db
        , allowPrivateTargets  = privateTargets
        , maxResponseBytes     = max 0 maxBytes
        , timeoutSeconds       = max 1 timeoutS
        , checkIntervalSeconds = max 5 intervalS
        , maxConcurrentChecks  = max 1 concurrency
        , basicAuthEnabled     = authEnabled
        , basicAuthUser        = authUser
        , basicAuthPass        = authPass
        }

-- Helpers ---------------------------------------------------------------

envStr :: String -> String -> IO String
envStr key def = fromMaybe def <$> lookupEnv key

envInt :: String -> Int -> IO Int
envInt key def = do
    mv <- lookupEnv key
    return $ case mv >>= readMaybe of
        Just n  -> n
        Nothing -> def

envBool :: String -> Bool -> IO Bool
envBool key def = do
    mv <- lookupEnv key
    return $ case mv of
        Just v  -> v `elem` ["true", "True", "1", "yes", "on"]
        Nothing -> def

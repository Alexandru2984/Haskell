{-# LANGUAGE OverloadedStrings #-}
module App.Config where

import System.Environment (lookupEnv)
import System.Directory (doesFileExist)
import Data.Maybe (fromMaybe)
import Text.Read (readMaybe)
import Control.Monad (unless, when, void)
import Configuration.Dotenv (loadFile, defaultConfig)
import Network.URI (parseURI, uriScheme, uriAuthority, uriPath, uriQuery, uriFragment, uriUserInfo, uriRegName)

data AppConfig = AppConfig
    { appPort :: Int, appHost :: String, dbUrl :: String
    , allowPrivateTargets :: Bool, maxResponseBytes :: Int, timeoutSeconds :: Int
    , checkIntervalSeconds :: Int, maxConcurrentChecks :: Int
    , basicAuthEnabled :: Bool, basicAuthUser :: String, basicAuthPass :: String
    , appOrigin :: String, retentionDays :: Int, maxEndpoints :: Int
    }
-- Deliberately no Show instance: configuration contains credentials.

defaultAppConfig :: AppConfig
defaultAppConfig = AppConfig 3060 "127.0.0.1" "" False 1048576 10 60 4 True "" ""
    "https://haskell.micutu.com" 0 200

loadConfig :: IO AppConfig
loadConfig = do
    hasEnv <- doesFileExist ".env"
    when hasEnv (void (loadFile defaultConfig))
    port <- envInt "APP_PORT" 3060 1 65535
    host <- envStr "APP_HOST" "127.0.0.1"
    db <- envStr "DATABASE_URL" ""
    private <- envBool "ALLOW_PRIVATE_TARGETS" False
    bytes <- envInt "MAX_RESPONSE_BYTES" 1048576 1 4194304
    timeoutS <- envInt "DEFAULT_TIMEOUT_SECONDS" 10 1 60
    interval <- envInt "DEFAULT_CHECK_INTERVAL_SECONDS" 60 5 86400
    concurrency <- envInt "MAX_CONCURRENT_CHECKS" 4 1 16
    auth <- envBool "APP_BASIC_AUTH_ENABLED" True
    user <- envStr "APP_USERNAME" ""
    pass <- envStr "APP_PASSWORD" ""
    origin <- envStr "APP_ORIGIN" "https://haskell.micutu.com"
    retention <- envInt "RETENTION_DAYS" 0 0 365
    endpointLimit <- envInt "MAX_ENDPOINTS" 200 1 1000
    environment <- envStr "APP_ENV" "production"
    unless (not (null db)) $ invalid "DATABASE_URL is required"
    when (auth && (null user || length pass < 16 || pass `elem` ["change_me_too", "change_me", "replace_with_a_unique_password_at_least_16_characters"])) $
        invalid "Basic authentication requires APP_USERNAME and an APP_PASSWORD of at least 16 characters"
    when (not auth && environment /= "development") $
        invalid "Authentication may only be disabled with APP_ENV=development"
    when (private && environment /= "development") $
        invalid "Private targets may only be enabled with APP_ENV=development"
    unless (validOrigin origin) $ invalid "APP_ORIGIN must be an http(s) origin without a path"
    pure $ AppConfig port host db private bytes timeoutS interval concurrency auth user pass origin retention endpointLimit

validOrigin :: String -> Bool
validOrigin s = case parseURI s of
    Just u -> uriScheme u `elem` ["http:", "https:"]
        && maybe False (\a -> null (uriUserInfo a) && not (null (uriRegName a))) (uriAuthority u)
        && null (uriPath u) && null (uriQuery u) && null (uriFragment u)
    _ -> False

invalid :: String -> IO a
invalid = ioError . userError

envStr :: String -> String -> IO String
envStr key def = fromMaybe def <$> lookupEnv key

envInt :: String -> Int -> Int -> Int -> IO Int
envInt key def lo hi = do
    value <- lookupEnv key
    case value of
        Nothing -> pure def
        Just raw -> case readMaybe raw of
            Just n | n >= lo && n <= hi -> pure n
            _ -> invalid (key ++ " must be an integer in " ++ show lo ++ ".." ++ show hi)

envBool :: String -> Bool -> IO Bool
envBool key def = do
    value <- lookupEnv key
    case value of
        Nothing -> pure def
        Just raw | raw `elem` ["true", "True", "1", "yes", "on"] -> pure True
                 | raw `elem` ["false", "False", "0", "no", "off"] -> pure False
                 | otherwise -> invalid (key ++ " must be true or false")

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module App.Checker where

import Network.HTTP.Client
import Network.HTTP.Types.Status (statusCode)
import Control.Exception (try, SomeException)
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Aeson (decode, Value(Null), toJSON)
import App.Types
import App.Config (AppConfig(..))
import App.Contract
import App.Security.UrlSafety (isSafeUrl)

checkEndpoint :: AppConfig -> Manager -> Endpoint -> IO CheckResult
checkEndpoint cfg manager endpoint = do
    start <- getCurrentTime
    safe <- isSafeUrl (allowPrivateTargets cfg) (endpointUrl endpoint)
    if not safe
        then return $ failure start 0 "Unsafe or private URL"
        else do
            ereq <- try (parseRequest (T.unpack (endpointUrl endpoint)))
                :: IO (Either SomeException Request)
            case ereq of
                Left e -> do
                    latency <- latencyFrom start
                    return $ failure start latency (T.pack (show e))
                Right req0 -> do
                    let req = req0
                            { method          = TE.encodeUtf8 (endpointMethod endpoint)
                            , responseTimeout = responseTimeoutMicro
                                                  (timeoutSeconds cfg * 1000000)
                            , redirectCount   = 0  -- do not follow redirects (SSRF)
                            }
                    result <- tryCheck cfg manager req
                    latency <- latencyFrom start
                    case result of
                        Left err -> return $ failure start latency (T.pack err)
                        Right (status, body) -> do
                            let bodyJson = maybe Null id (decode body)
                                errors   = validateContract (endpointContract endpoint) bodyJson
                                passed   = null errors && status < 400
                            return $ CheckResult 0 (endpointId endpoint) start
                                       status latency passed (toJSON errors)
  where
    failure start latency msg =
        CheckResult 0 (endpointId endpoint) start 0 latency False
            (toJSON [ValidationError "$" msg])

-- | Milliseconds elapsed since the given start time.
latencyFrom :: UTCTime -> IO Int
latencyFrom start = do
    end <- getCurrentTime
    return $ round (diffUTCTime end start * 1000)

-- | Read the response with a hard cap on the body size to avoid OOM on a
-- hostile or huge endpoint. Any 'HttpException' (timeout, connection refused,
-- TLS error, …) is turned into a 'Left' instead of propagating.
tryCheck :: AppConfig -> Manager -> Request -> IO (Either String (Int, LBS.ByteString))
tryCheck cfg manager req = do
    result <- try $ withResponse req manager $ \resp -> do
        let status = statusCode (responseStatus resp)
        body <- brReadSome (responseBody resp) (maxResponseBytes cfg)
        return (status, body)
    return $ case result of
        Left (e :: SomeException) -> Left (show e)
        Right ok                  -> Right ok

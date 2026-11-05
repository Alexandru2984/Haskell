{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module App.Checker where

import Network.HTTP.Client
import Network.HTTP.Client.Internal (hostAddress)
import Network.HTTP.Types.Status (statusCode)
import Control.Exception (try)
import Control.Exception (evaluate)
import System.Timeout (timeout)
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Aeson (eitherDecode, toJSON, encode)
import App.Types
import App.Config (AppConfig(..))
import App.Contract
import App.Security.UrlSafety (resolveSafeAddress)

checkEndpoint :: AppConfig -> Manager -> Endpoint -> IO CheckResult
checkEndpoint cfg manager endpoint = do
    start <- getCurrentTime
    result <- timeout (timeoutSeconds cfg * 1000000) $ do
        target <- resolveSafeAddress (allowPrivateTargets cfg) (endpointUrl endpoint)
        case target of
            Left err -> pure (Left err)
            Right _ | endpointMethod endpoint `notElem` ["GET", "HEAD"] -> pure (Left "Only read-only GET and HEAD monitoring is supported")
            Right ip -> do
                parsed <- try (parseRequest (T.unpack (endpointUrl endpoint))) :: IO (Either HttpException Request)
                case parsed of
                    Left _ -> pure (Left "Invalid HTTP request URL")
                    Right req0 -> do
                        let req = req0 { method = TE.encodeUtf8 (endpointMethod endpoint)
                            , hostAddress = Just ip, proxy = Nothing, redirectCount = 0
                            , requestHeaders = [("Accept", "application/json"), ("Accept-Encoding", "identity")]
                            , responseTimeout = responseTimeoutMicro (timeoutSeconds cfg * 1000000)
                            , checkResponse = \_ _ -> pure () }
                        fetched <- tryCheck cfg manager req
                        case fetched of
                            Left err -> pure (Left (T.pack err))
                            Right (status, body) -> do
                                let httpErrors = [ValidationError "$" ("Unexpected HTTP status " <> T.pack (show status)) | status < 200 || status >= 300]
                                    jsonErrors = if endpointMethod endpoint == "HEAD" then [] else case eitherDecode body of
                                        Left _ -> [ValidationError "$" "Response is not valid JSON"]
                                        Right value -> take 100 (validateContract (endpointContract endpoint) value)
                                    definitionErrors = [ValidationError "$" "Stored contract definition is invalid" | not (null (validateDefinition (endpointContract endpoint)))]
                                    errors = httpErrors ++ definitionErrors ++ jsonErrors
                                -- Force validation before leaving the deadline, not lazily in persistence.
                                _ <- evaluate (LBS.length (encode (toJSON errors)))
                                pure (Right (status, errors))
    latency <- latencyFrom start
    let (status, errors) = case result of
            Nothing -> (0, [ValidationError "$" "Check exceeded its total deadline"])
            Just (Left err) -> (0, [ValidationError "$" err])
            Just (Right r) -> r
    pure $ CheckResult 0 (endpointId endpoint) start status latency (null errors) (toJSON errors)

latencyFrom :: UTCTime -> IO Int
latencyFrom start = max 0 . round . (* 1000) . (`diffUTCTime` start) <$> getCurrentTime

-- Never store exception text: http-client exceptions may embed target URLs or credentials.
tryCheck :: AppConfig -> Manager -> Request -> IO (Either String (Int, LBS.ByteString))
tryCheck cfg manager req = do
    fetched <- try $ withResponse req manager $ \resp -> do
        body <- readLimited (maxResponseBytes cfg) (responseBody resp)
        pure ((,) (statusCode (responseStatus resp)) <$> body)
    pure $ case fetched of
        Left (_ :: HttpException) -> Left "HTTP connection, TLS or response timeout failure"
        Right result -> result

readLimited :: Int -> BodyReader -> IO (Either String LBS.ByteString)
readLimited limit reader = go 0 []
  where
    go size chunks = do
        chunk <- brRead reader
        if BS.null chunk then pure (Right (LBS.fromChunks (reverse chunks)))
        else if BS.length chunk > limit - size then pure (Left "Response exceeds configured size limit")
        else go (size + BS.length chunk) (chunk : chunks)

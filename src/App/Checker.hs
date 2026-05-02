{-# LANGUAGE OverloadedStrings #-}
module App.Checker where

import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Aeson (decode, Value(Null), toJSON)
import App.Types
import App.Contract
import App.Security.UrlSafety (isSafeUrl)

checkEndpoint :: Bool -> Manager -> Endpoint -> IO CheckResult
checkEndpoint allowPrivate manager endpoint = do
    start <- getCurrentTime
    
    if not (isSafeUrl allowPrivate (endpointUrl endpoint))
        then return $ CheckResult 0 (endpointId endpoint) start 0 0 False (toJSON [ValidationError "$" "Unsafe or private URL"])
        else do
            req <- parseRequest (T.unpack $ endpointUrl endpoint)
            let req' = req { method = TE.encodeUtf8 $ endpointMethod endpoint
                           , responseTimeout = responseTimeoutMicro $ 10 * 1000000 -- 10 seconds
                           }
            
            result <- tryCheck manager req'
            
            end <- getCurrentTime
            let latency = round $ diffUTCTime end start * 1000
            
            case result of
                Left err -> return $ CheckResult 0 (endpointId endpoint) start 0 latency False (toJSON [ValidationError "$" (T.pack err)])
                Right (status, body) -> do
                    let bodyJson = case decode body of
                            Just v -> v
                            Nothing -> Null
                        
                    let errors = validateContract (endpointContract endpoint) bodyJson
                        passed = null errors && status < 400 -- simplify
                        
                    return $ CheckResult 0 (endpointId endpoint) start status latency passed (toJSON errors)

tryCheck :: Manager -> Request -> IO (Either String (Int, LBS.ByteString))
tryCheck manager req = do
    -- Simplified try/catch
    resp <- httpLbs req manager
    return $ Right (statusCode $ responseStatus resp, responseBody resp)

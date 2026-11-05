{-# LANGUAGE OverloadedStrings #-}
module App.Security.Web (securityHeaders, protectWrites, trustedWrite) where

import App.Config
import Network.Wai
import Network.HTTP.Types
import Network.URI (parseURI, uriScheme, uriAuthority, uriUserInfo, uriRegName, uriPort)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BC
import Data.IORef

securityHeaders :: Middleware
securityHeaders application request respond = application request $ respond . mapResponseHeaders (headers ++)
  where
    headers =
        [ ("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
        , ("X-Content-Type-Options", "nosniff"), ("X-Frame-Options", "DENY")
        , ("Referrer-Policy", "no-referrer"), ("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        , ("Cache-Control", "no-store"), ("X-Robots-Tag", "noindex, nofollow") ]

-- Require browser-supplied source origin for EVERY mutation, including requests
-- without Fetch Metadata. Never derive trust from Host or forwarded headers.
trustedWrite :: String -> Request -> Bool
trustedWrite origin request = fetchOK && sourceOK
  where
    headers = requestHeaders request
    fetchOK = maybe True (`elem` ["same-origin", "none"]) (lookup "Sec-Fetch-Site" headers)
    sourceOK = case lookup "Origin" headers of
        Just value -> value == BC.pack origin
        Nothing -> case lookup "Referer" headers >>= parseURI . BC.unpack of
            Just u -> maybe False (\a -> null (uriUserInfo a) && uriScheme u ++ "//" ++ uriRegName a ++ uriPort a == origin) (uriAuthority u)
            _ -> False

protectWrites :: AppConfig -> Middleware
protectWrites cfg application request respond
    | requestMethod request `elem` [methodGet, methodHead, methodOptions] = application request respond
    | not (trustedWrite (appOrigin cfg) request) = respond $ responseLBS status403 [(hContentType,"text/plain; charset=utf-8")] "Untrusted request origin. Reload the form from this site."
    | otherwise = do
        let cap = 131072
        case requestBodyLength request of
            KnownLength n | n > fromIntegral cap -> tooLarge
            _ -> do
                body <- collect cap []
                case body of
                    Nothing -> tooLarge
                    Just bytes -> do
                        remaining <- newIORef bytes
                        let replay = atomicModifyIORef' remaining (\b -> (BS.empty,b))
                        application (setRequestBodyChunks replay request { requestBodyLength = KnownLength (fromIntegral (BS.length bytes)) }) respond
  where
    tooLarge = respond $ responseLBS status413 [(hContentType,"text/plain; charset=utf-8")] "Request body exceeds 128 KiB."
    collect left chunks = do
        chunk <- getRequestBodyChunk request
        if BS.null chunk then pure (Just (BS.concat (reverse chunks)))
        else if BS.length chunk > left then pure Nothing
        else collect (left - BS.length chunk) (chunk:chunks)

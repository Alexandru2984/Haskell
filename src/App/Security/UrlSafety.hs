{-# LANGUAGE OverloadedStrings #-}
module App.Security.UrlSafety where

import Network.URI
import qualified Data.Text as T
import Data.Maybe (fromMaybe)

isSafeUrl :: Bool -> T.Text -> Bool
isSafeUrl allowPrivate txt = 
    case parseURI (T.unpack txt) of
        Nothing -> False
        Just uri -> 
            let scheme = uriScheme uri
                auth = uriAuthority uri
                host = fromMaybe "" (uriRegName <$> auth)
            in (scheme == "http:" || scheme == "https:") && (allowPrivate || not (isPrivateHost host))

isPrivateHost :: String -> Bool
isPrivateHost host =
    host == "localhost" ||
    host == "127.0.0.1" ||
    host == "::1" ||
    "10." `isPrefixOf` host ||
    "192.168." `isPrefixOf` host ||
    "169.254." `isPrefixOf` host ||
    "172.16." `isPrefixOf` host || -- Simplified check for 172.16.0.0/12
    "172.17." `isPrefixOf` host ||
    "172.18." `isPrefixOf` host ||
    "172.19." `isPrefixOf` host ||
    "172.2" `isPrefixOf` host ||
    "172.30." `isPrefixOf` host ||
    "172.31." `isPrefixOf` host ||
    "fd" `isPrefixOf` host -- IPv6 Unique Local Address

isPrefixOf :: String -> String -> Bool
isPrefixOf prefix str = take (length prefix) str == prefix
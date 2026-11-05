{-# LANGUAGE OverloadedStrings #-}
module App.Security.UrlSafety
    ( isSafeUrl, resolveSafeAddress, validTargetUrl, isPrivateIPv4, isPrivateIPv6 ) where

import Network.URI (parseURI, uriScheme, uriFragment, uriAuthority, uriUserInfo, uriRegName, uriPort)
import Network.Socket
import Control.Exception (try, IOException)
import Data.Bits (shiftR, (.&.))
import Data.Char (isControl, isSpace, isDigit)
import Data.Word (Word8, Word16)
import Text.Read (readMaybe)
import qualified Data.Text as T

-- Parse the exact string that will reach http-client. Never trim one parser's input only.
validTargetUrl :: T.Text -> Bool
validTargetUrl txt = T.length txt <= 2048 && not (T.any (\c -> isControl c || isSpace c || c == '\\') txt)
    && case parseURI (T.unpack txt) of
        Just u -> uriScheme u `elem` ["http:", "https:"] && null (uriFragment u)
            && case uriAuthority u of
                Just a -> null (uriUserInfo a) && not (null (uriRegName a)) && validPort (uriPort a)
                _ -> False
        _ -> False
  where
    validPort "" = True
    validPort (':' : xs) = not (null xs) && all isDigit xs && case readMaybe xs :: Maybe Int of
        Just p -> p >= 1 && p <= 65535
        _ -> False
    validPort _ = False

isSafeUrl :: Bool -> T.Text -> IO Bool
isSafeUrl allowPrivate txt = either (const False) (const True) <$> resolveSafeAddress allowPrivate txt

-- http-client's hostAddress pins an IPv4 address while retaining the original host for
-- Host, TLS SNI and certificate validation. IPv6-only targets fail closed explicitly.
resolveSafeAddress :: Bool -> T.Text -> IO (Either T.Text HostAddress)
resolveSafeAddress allowPrivate txt
    | not (validTargetUrl txt) = pure (Left "Use a valid HTTP(S) URL without credentials, spaces or fragments")
    | otherwise = case parseURI (T.unpack txt) >>= uriAuthority of
        Nothing -> pure (Left "Invalid URL")
        Just authority -> do
            let host = filter (`notElem` ("[]" :: String)) (uriRegName authority)
            result <- try (getAddrInfo (Just defaultHints { addrSocketType = Stream }) (Just host) Nothing)
                :: IO (Either IOException [AddrInfo])
            pure $ case result of
                Left _ -> Left "Target DNS resolution failed"
                Right infos
                    | null infos -> Left "Target DNS resolution returned no addresses"
                    | not allowPrivate && not (all (addrIsPublic . addrAddress) infos) -> Left "Unsafe or private URL"
                    | otherwise -> case [ip | AddrInfo { addrAddress = SockAddrInet _ ip } <- infos] of
                        ip : _ -> Right ip
                        [] -> Left "An IPv4-reachable target is required for pinned connections"

addrIsPublic :: SockAddr -> Bool
addrIsPublic (SockAddrInet _ ip) = not (isPrivateIPv4 (hostAddressToTuple ip))
addrIsPublic (SockAddrInet6 _ _ ip _) = not (isPrivateIPv6 (hostAddress6ToTuple ip))
addrIsPublic _ = False

isPrivateIPv4 :: (Word8, Word8, Word8, Word8) -> Bool
isPrivateIPv4 (a,b,c,_) = a `elem` [0,10,127] || a >= 224
    || (a == 100 && b >= 64 && b <= 127)
    || (a == 169 && b == 254) || (a == 172 && b >= 16 && b <= 31)
    || (a == 192 && (b == 168 || (b == 0 && c `elem` [0,2]) || (b == 88 && c == 99)))
    || (a == 198 && (b `elem` [18,19] || (b == 51 && c == 100)))
    || (a == 203 && b == 0 && c == 113)

isPrivateIPv6 :: (Word16,Word16,Word16,Word16,Word16,Word16,Word16,Word16) -> Bool
isPrivateIPv6 (a,b,c,d,e,f,g,h)
    | (a,b,c,d,e,f) == (0,0,0,0,0,0xffff) =
        isPrivateIPv4 (fromIntegral (g `shiftR` 8), fromIntegral g,
                       fromIntegral (h `shiftR` 8), fromIntegral h)
    -- Allow ordinary global unicast only. Refuse transition, documentation and special space.
    | a .&. 0xe000 /= 0x2000 = True
    | a == 0x2002 = True -- 6to4 embeds an IPv4 destination
    | a == 0x2001 && (b < 0x0200 || b == 0x0db8) = True
    | a == 0x3fff && b .&. 0xf000 == 0 = True -- documentation /20
    | otherwise = False

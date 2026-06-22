{-# LANGUAGE OverloadedStrings #-}

-- | URL safety checks to mitigate SSRF.
--
-- Unlike a naive string-prefix check, this resolves the host via DNS and
-- validates every resolved IPv4/IPv6 address against private, loopback,
-- link-local, CGNAT, and reserved ranges. Blocking is conservative: if ANY
-- resolved address falls in a forbidden range (or resolution fails), the URL
-- is rejected. This defeats DNS-rebinding tricks where a public hostname
-- points at an internal address such as the cloud metadata endpoint.
module App.Security.UrlSafety
    ( isSafeUrl
    , isPrivateIPv4
    , isPrivateIPv6
    ) where

import Network.URI (parseURI, uriScheme, uriAuthority, uriRegName)
import Network.Socket
    ( getAddrInfo, defaultHints, AddrInfo(..), SockAddr(..)
    , SocketType(Stream), hostAddressToTuple, hostAddress6ToTuple )
import Control.Exception (try, SomeException)
import Data.Bits (shiftR, (.&.))
import Data.Char (toLower)
import Data.Word (Word8, Word16)
import qualified Data.Text as T

-- | Is this URL safe to fetch? Requires DNS resolution, hence 'IO'.
-- When @allowPrivate@ is 'True' the IP-range checks are skipped (still
-- requires a valid http/https URL).
isSafeUrl :: Bool -> T.Text -> IO Bool
isSafeUrl allowPrivate txt =
    case parseURI (T.unpack (T.strip txt)) of
        Nothing  -> return False
        Just uri
            | not (schemeOk (uriScheme uri)) -> return False
            | otherwise -> case uriAuthority uri of
                Nothing   -> return False
                Just auth ->
                    let host = stripBrackets (uriRegName auth)
                    in if null host
                        then return False
                        else if allowPrivate
                            then return True
                            else do
                                eaddrs <- try (resolve host)
                                    :: IO (Either SomeException [SockAddr])
                                case eaddrs of
                                    Left _         -> return False
                                    Right []       -> return False
                                    Right addrs    -> return (all addrIsPublic addrs)

schemeOk :: String -> Bool
schemeOk s = map toLower s `elem` ["http:", "https:"]

stripBrackets :: String -> String
stripBrackets s = case s of
    ('[' : rest) -> takeWhile (/= ']') rest
    _            -> s

resolve :: String -> IO [SockAddr]
resolve host = do
    let hints = defaultHints { addrSocketType = Stream }
    infos <- getAddrInfo (Just hints) (Just host) Nothing
    return (map addrAddress infos)

addrIsPublic :: SockAddr -> Bool
addrIsPublic (SockAddrInet  _ ha)     = not (isPrivateIPv4 (hostAddressToTuple ha))
addrIsPublic (SockAddrInet6 _ _ ha6 _) = not (isPrivateIPv6 (hostAddress6ToTuple ha6))
addrIsPublic _                        = False  -- unix/other: refuse

-- | IPv4 ranges that must never be probed.
isPrivateIPv4 :: (Word8, Word8, Word8, Word8) -> Bool
isPrivateIPv4 (a, b, _, _) =
       a == 0                          -- 0.0.0.0/8   "this" network
    || a == 10                         -- 10.0.0.0/8  private
    || (a == 100 && b >= 64 && b <= 127) -- 100.64.0.0/10 CGNAT
    || a == 127                        -- 127.0.0.0/8 loopback
    || (a == 169 && b == 254)          -- 169.254.0.0/16 link-local + metadata
    || (a == 172 && b >= 16 && b <= 31)  -- 172.16.0.0/12 private
    || (a == 192 && b == 168)          -- 192.168.0.0/16 private
    || (a == 198 && (b == 18 || b == 19)) -- 198.18.0.0/15 benchmark
    || a >= 224                        -- 224.0.0.0/4 multicast + 240/4 reserved

-- | IPv6 ranges that must never be probed.
isPrivateIPv6 :: (Word16, Word16, Word16, Word16, Word16, Word16, Word16, Word16) -> Bool
isPrivateIPv6 grp@(g0, g1, g2, g3, g4, g5, g6, g7)
    | g0 == 0 && g1 == 0 && g2 == 0 && g3 == 0
      && g4 == 0 && g5 == 0 && g6 == 0 && g7 <= 1 = True   -- :: and ::1
    | g0 == 0 && g1 == 0 && g2 == 0 && g3 == 0
      && g4 == 0 && g5 == 0xffff                  = isPrivateIPv4 (mappedV4 grp) -- ::ffff:a.b.c.d
    | firstByte == 0xfc || firstByte == 0xfd      = True   -- fc00::/7 unique-local
    | firstByte == 0xfe && (secondNibble == 0x8)  = True   -- fe80::/10 link-local
    | firstByte == 0xff                           = True   -- ff00::/8 multicast
    | otherwise                                   = False
  where
    firstByte    = fromIntegral (g0 `shiftR` 8) :: Word8
    secondNibble = fromIntegral ((g0 `shiftR` 4) .&. 0xf) :: Word8

mappedV4 :: (Word16, Word16, Word16, Word16, Word16, Word16, Word16, Word16)
         -> (Word8, Word8, Word8, Word8)
mappedV4 (_, _, _, _, _, _, g6, g7) =
    ( fromIntegral (g6 `shiftR` 8)
    , fromIntegral (g6 .&. 0xff)
    , fromIntegral (g7 `shiftR` 8)
    , fromIntegral (g7 .&. 0xff) )

{-# LANGUAGE OverloadedStrings #-}
module App.UrlSafetySpec (spec) where

import Test.Hspec
import App.Security.UrlSafety

spec :: Spec
spec = do
  describe "UrlSafety" $ do
    it "blocks loopback" $
      isSafeUrl False "http://127.0.0.1/api" `shouldReturn` False
    it "blocks the cloud metadata address" $
      isSafeUrl False "http://169.254.169.254/latest/meta-data" `shouldReturn` False
    it "blocks IPv6 loopback" $
      isSafeUrl False "http://[::1]/api" `shouldReturn` False
    it "allows a public IP literal" $
      isSafeUrl False "http://1.1.1.1/api" `shouldReturn` True
    it "rejects non-http schemes" $
      isSafeUrl False "file:///etc/passwd" `shouldReturn` False

  describe "isPrivateIPv4" $ do
    it "flags loopback, private, CGNAT, link-local ranges" $ do
      isPrivateIPv4 (127, 0, 0, 1)        `shouldBe` True
      isPrivateIPv4 (10, 1, 2, 3)         `shouldBe` True
      isPrivateIPv4 (192, 168, 0, 1)      `shouldBe` True
      isPrivateIPv4 (172, 16, 0, 1)       `shouldBe` True
      isPrivateIPv4 (172, 31, 255, 255)   `shouldBe` True
      isPrivateIPv4 (100, 64, 0, 1)       `shouldBe` True
      isPrivateIPv4 (169, 254, 169, 254)  `shouldBe` True
      isPrivateIPv4 (0, 0, 0, 0)          `shouldBe` True
    it "allows genuine public addresses" $ do
      isPrivateIPv4 (1, 1, 1, 1)          `shouldBe` False
      isPrivateIPv4 (8, 8, 8, 8)          `shouldBe` False
      isPrivateIPv4 (172, 32, 0, 1)       `shouldBe` False
      isPrivateIPv4 (172, 15, 0, 1)       `shouldBe` False
      isPrivateIPv4 (172, 200, 0, 1)      `shouldBe` False

  describe "isPrivateIPv6" $ do
    it "flags loopback, ULA, link-local and mapped IPv4" $ do
      isPrivateIPv6 (0,0,0,0,0,0,0,1)               `shouldBe` True   -- ::1
      isPrivateIPv6 (0xfd00,0,0,0,0,0,0,1)          `shouldBe` True   -- fd00::/8 ULA
      isPrivateIPv6 (0xfe80,0,0,0,0,0,0,1)          `shouldBe` True   -- fe80::/10
      isPrivateIPv6 (0,0,0,0,0,0xffff,0xa9fe,0xa9fe) `shouldBe` True  -- ::ffff:169.254.169.254
    it "allows a public mapped IPv4" $
      isPrivateIPv6 (0,0,0,0,0,0xffff,0x0101,0x0101) `shouldBe` False  -- ::ffff:1.1.1.1
    it "blocks the full IPv6 link-local range and transition addresses" $ do
      isPrivateIPv6 (0xfe90,0,0,0,0,0,0,1) `shouldBe` True
      isPrivateIPv6 (0xfebf,0,0,0,0,0,0,1) `shouldBe` True
      isPrivateIPv6 (0x2002,0x7f00,1,0,0,0,0,1) `shouldBe` True
      isPrivateIPv6 (0x2001,0xdb8,0,0,0,0,0,1) `shouldBe` True
  describe "URL syntax" $ do
    it "rejects credentials, fragments, malformed ports, whitespace and backslashes" $
      map validTargetUrl ["https://u:p@example.com/", "https://example.com/#x", "http://example.com:99999/", " https://example.com/", "http://example.com/a b"] `shouldBe` replicate 5 False
    it "blocks documentation and protocol-assignment IPv4" $
      map isPrivateIPv4 [(192,0,0,1),(192,0,2,1),(198,51,100,1),(203,0,113,1)] `shouldBe` replicate 4 True

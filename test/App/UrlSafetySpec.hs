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
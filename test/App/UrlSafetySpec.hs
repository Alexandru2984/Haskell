{-# LANGUAGE OverloadedStrings #-}
module App.UrlSafetySpec (spec) where

import Test.Hspec
import App.Security.UrlSafety

spec :: Spec
spec = do
  describe "UrlSafety" $ do
    it "blocks private IPs" $ do
      isSafeUrl False "http://127.0.0.1/api" `shouldBe` False
    it "allows public IPs" $ do
      isSafeUrl False "http://google.com/api" `shouldBe` True
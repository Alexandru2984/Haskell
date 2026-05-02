{-# LANGUAGE OverloadedStrings #-}
module App.ValidatorSpec (spec) where

import Test.Hspec

spec :: Spec
spec = do
  describe "Validator" $ do
    it "works" $ do
      True `shouldBe` True
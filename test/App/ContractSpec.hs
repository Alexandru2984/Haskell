{-# LANGUAGE OverloadedStrings #-}
module App.ContractSpec (spec) where

import Test.Hspec
import App.Contract
import Data.Aeson

spec :: Spec
spec = do
  describe "Contract Validation" $ do
    it "validates basic structure" $ do
      let expected = object [ "type" .= String "object", "allow_extra_fields" .= Bool True ]
          actual = object [ "key" .= String "value" ]
      validateContract expected actual `shouldBe` []
{-# LANGUAGE OverloadedStrings #-}
module App.ValidatorSpec (spec) where

import Test.Hspec
import App.Validator (validate)
import App.Contract (validateContract)
import Data.Aeson

spec :: Spec
spec = do
  describe "validate" $ do
    it "agrees with validateContract" $ do
      let expected = object [ "type" .= String "object", "allow_extra_fields" .= Bool True ]
          actual   = object [ "k" .= String "v" ]
      validate expected actual `shouldBe` validateContract expected actual

    it "reports the same errors as validateContract on mismatch" $ do
      let expected = object [ "type" .= String "object" ]
          actual   = object [ "extra" .= String "v" ]
      validate expected actual `shouldBe` validateContract expected actual

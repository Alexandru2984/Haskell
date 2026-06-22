{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module App.ContractSpec (spec) where

import Test.Hspec
import Test.QuickCheck
import App.Contract
import Data.Aeson
import Data.Aeson.Key (fromText)
import qualified Data.Text as T

spec :: Spec
spec = do
  describe "validateContract" $ do
    it "accepts an object when extra fields are allowed" $ do
      let expected = object [ "type" .= String "object", "allow_extra_fields" .= Bool True ]
          actual   = object [ "key" .= String "value" ]
      validateContract expected actual `shouldBe` []

    it "accepts a present required field of the correct type" $ do
      let expected = object
            [ "type" .= String "object"
            , "required" .= object [ "status" .= object [ "type" .= String "string" ] ]
            , "allow_extra_fields" .= Bool True ]
          actual = object [ "status" .= String "ok" ]
      validateContract expected actual `shouldBe` []

    it "flags a missing required field" $ do
      let expected = object
            [ "type" .= String "object"
            , "required" .= object [ "status" .= object [ "type" .= String "string" ] ] ]
          actual = object [ ]
      map errorMessage (validateContract expected actual)
        `shouldBe` ["Missing required field"]

    it "flags a type mismatch" $ do
      let expected = object
            [ "type" .= String "object"
            , "required" .= object [ "n" .= object [ "type" .= String "number" ] ]
            , "allow_extra_fields" .= Bool True ]
          actual = object [ "n" .= String "not a number" ]
      length (validateContract expected actual) `shouldBe` 1

    it "rejects extra fields when not allowed" $ do
      let expected = object [ "type" .= String "object" ]
          actual   = object [ "surprise" .= String "x" ]
      map errorMessage (validateContract expected actual)
        `shouldBe` ["Extra field not allowed"]

    it "accepts a whole number as integer" $ do
      let expected = object
            [ "type" .= String "object"
            , "required" .= object [ "n" .= object [ "type" .= String "integer" ] ]
            , "allow_extra_fields" .= Bool True ]
          actual = object [ "n" .= Number 42 ]
      validateContract expected actual `shouldBe` []

    it "rejects a fractional number as integer" $ do
      let expected = object
            [ "type" .= String "object"
            , "required" .= object [ "n" .= object [ "type" .= String "integer" ] ]
            , "allow_extra_fields" .= Bool True ]
          actual = object [ "n" .= Number 3.14 ]
      length (validateContract expected actual) `shouldBe` 1

    it "validates array item types" $ do
      let expected = object
            [ "type" .= String "object"
            , "required" .= object
                [ "xs" .= object
                    [ "type" .= String "array"
                    , "items" .= object [ "type" .= String "number" ] ] ]
            , "allow_extra_fields" .= Bool True ]
          actual = object [ "xs" .= [Number 1, Number 2] ]
      validateContract expected actual `shouldBe` []

    it "accepts every required string field (property)" $ property $ \(keys :: [String]) ->
      let uniq      = dedupe (filter (not . T.null) (map T.pack keys))
          required  = object [ fromText k .= object ["type" .= String "string"] | k <- uniq ]
          expected  = object [ "type" .= String "object"
                             , "required" .= required
                             , "allow_extra_fields" .= Bool True ]
          actual    = object [ fromText k .= String "v" | k <- uniq ]
      in validateContract expected actual == []

dedupe :: Eq a => [a] -> [a]
dedupe = foldr (\x acc -> if x `elem` acc then acc else x : acc) []

module App.ScoringSpec (spec) where

import Test.Hspec

spec :: Spec
spec = do
  describe "Scoring" $ do
    it "works" $ do
      True `shouldBe` True
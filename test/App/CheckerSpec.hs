module App.CheckerSpec (spec) where

import Test.Hspec

spec :: Spec
spec = do
  describe "Checker" $ do
    it "works" $ do
      True `shouldBe` True
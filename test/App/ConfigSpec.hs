{-# LANGUAGE OverloadedStrings #-}
module App.ConfigSpec (spec) where
import Test.Hspec
import App.Config
import Control.Exception (bracket)
import System.Environment (lookupEnv,setEnv,unsetEnv)

spec :: Spec
spec = do
  describe "configuration validation" $ do
    it "rejects malformed and out-of-range integers" $ do
      withValue "PULSE_TEST_INT" "oops" (envInt "PULSE_TEST_INT" 4 1 16) `shouldThrow` anyIOException
      withValue "PULSE_TEST_INT" "0" (envInt "PULSE_TEST_INT" 4 1 16) `shouldThrow` anyIOException
      withValue "PULSE_TEST_INT" "17" (envInt "PULSE_TEST_INT" 4 1 16) `shouldThrow` anyIOException
      withValue "PULSE_TEST_INT" "8" (envInt "PULSE_TEST_INT" 4 1 16) `shouldReturn` 8
    it "rejects unrecognized boolean values" $
      withValue "PULSE_TEST_BOOL" "treu" (envBool "PULSE_TEST_BOOL" False) `shouldThrow` anyIOException
    it "requires an exact HTTP(S) origin" $ do
      map validOrigin ["https://haskell.micutu.com","http://127.0.0.1:19060"] `shouldBe` [True,True]
      map validOrigin ["https://haskell.micutu.com/","https://u:p@example.com","https://example.com?q=x","file:///foo"] `shouldBe` replicate 4 False

withValue :: String -> String -> IO a -> IO a
withValue key value action = bracket (lookupEnv key) restore (\_ -> setEnv key value >> action)
  where restore Nothing = unsetEnv key
        restore (Just previous) = setEnv key previous

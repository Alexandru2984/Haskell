{-# LANGUAGE OverloadedStrings #-}
module App.CheckerSpec (spec) where

import Test.Hspec
import Control.Concurrent (threadDelay)
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Network.Wai (responseLBS, responseStream, pathInfo)
import Network.Wai.Handler.Warp (testWithApplication)
import Network.HTTP.Types (status200, status302, status500)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as LBS
import Data.Aeson (Value(Null), object, (.=), toJSON)
import App.Checker (checkEndpoint)
import App.Config (AppConfig(..), defaultAppConfig)
import App.Types

spec :: Spec
spec = do
  describe "checkEndpoint" $ do
    it "refuses a private/loopback target without hitting the network" $ do
      manager <- newManager defaultManagerSettings
      let ep = Endpoint
                 { endpointId       = 1
                 , endpointName     = "local"
                 , endpointProject  = "test"
                 , endpointUrl      = "http://127.0.0.1:1/secret"
                 , endpointMethod   = "GET"
                 , endpointStatus   = Unknown
                 , endpointEnabled  = True
                 , endpointContract = Null
                 }
      result <- checkEndpoint testConfig manager ep
      checkPassed result `shouldBe` False
      checkStatus result `shouldBe` 0

    it "fails invalid JSON, redirects, HTTP errors and oversized responses" $
      testWithApplication (pure fixture) $ \port -> do
        manager <- newManager defaultManagerSettings
        let cfg = testConfig { allowPrivateTargets = True, maxResponseBytes = 1024 }
            ep path = Endpoint 1 "fixture" "test" ("http://127.0.0.1:" <> T.pack (show port) <> path) "GET" Unknown True (object ["type" .= ("null" :: T.Text)])
        exact <- checkEndpoint cfg manager (ep "/exact")
        checkPassed exact `shouldBe` True
        slow <- checkEndpoint (cfg {timeoutSeconds = 1}) manager (ep "/slow")
        checkPassed slow `shouldBe` False
        checkStatus slow `shouldBe` 0
        headResult <- checkEndpoint cfg manager ((ep "/invalid") {endpointMethod = "HEAD"})
        checkPassed headResult `shouldBe` True
        good <- checkEndpoint cfg manager (ep "/good")
        checkPassed good `shouldBe` True
        mapM_ (\path -> do
          result <- checkEndpoint cfg manager (ep path)
          checkPassed result `shouldBe` False
          checkErrors result `shouldNotBe` encodeEmpty) ["/invalid", "/redirect", "/error", "/huge"]
  where
    encodeEmpty = toJSON ([] :: [T.Text])
    fixture request respond = respond $ case pathInfo request of
      ["slow"] -> responseStream status200 [] (\write flush -> do write "null"; flush; threadDelay 2000000)
      ["exact"] -> responseLBS status200 [] ("null" <> LBS.replicate 1020 32)
      ["good"] -> responseLBS status200 [] "null"
      ["redirect"] -> responseLBS status302 [("Location", "/good")] "null"
      ["error"] -> responseLBS status500 [] "null"
      ["huge"] -> responseLBS status200 [] (LBS.replicate 2048 32)
      _ -> responseLBS status200 [] "not-json"

testConfig :: AppConfig
testConfig = defaultAppConfig { basicAuthEnabled = False, maxResponseBytes = 1024, timeoutSeconds = 2 }

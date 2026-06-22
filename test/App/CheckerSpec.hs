{-# LANGUAGE OverloadedStrings #-}
module App.CheckerSpec (spec) where

import Test.Hspec
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Data.Aeson (Value(Null))
import App.Checker (checkEndpoint)
import App.Config (AppConfig(..))
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

testConfig :: AppConfig
testConfig = AppConfig
    { appPort              = 0
    , appHost              = "127.0.0.1"
    , dbUrl                = ""
    , allowPrivateTargets  = False
    , maxResponseBytes     = 1024
    , timeoutSeconds       = 5
    , checkIntervalSeconds = 60
    , maxConcurrentChecks  = 1
    , basicAuthEnabled     = False
    , basicAuthUser        = ""
    , basicAuthPass        = ""
    }

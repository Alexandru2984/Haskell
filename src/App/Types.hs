{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
module App.Types where

import Data.Aeson
import GHC.Generics
import Data.Time (UTCTime)
import qualified Data.Text as T

data Endpoint = Endpoint
    { endpointId :: Int
    , endpointName :: T.Text
    , endpointProject :: T.Text
    , endpointUrl :: T.Text
    , endpointMethod :: T.Text
    , endpointStatus :: Int
    , endpointEnabled :: Bool
    , endpointContract :: Value
    } deriving (Show, Generic)

instance ToJSON Endpoint
instance FromJSON Endpoint

data CheckResult = CheckResult
    { checkId :: Int
    , checkEndpointId :: Int
    , checkTime :: UTCTime
    , checkStatus :: Int
    , checkLatencyMs :: Int
    , checkPassed :: Bool
    , checkErrors :: Value
    } deriving (Show, Generic)

instance ToJSON CheckResult
instance FromJSON CheckResult
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
module App.Types where

import Data.Aeson
import GHC.Generics
import Data.Time (UTCTime)
import qualified Data.Text as T
import Database.PostgreSQL.Simple.FromRow
import Database.PostgreSQL.Simple.ToRow

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

instance FromRow Endpoint where
    fromRow = Endpoint <$> field <*> field <*> field <*> field <*> field <*> field <*> field <*> field

instance ToRow Endpoint where
    toRow (Endpoint id' name proj url method status enabled contract) = 
        toRow (id', name, proj, url, method, status, enabled, contract)

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

instance FromRow CheckResult where
    fromRow = CheckResult <$> field <*> field <*> field <*> field <*> field <*> field <*> field

data Health = Health
    { healthStatus    :: T.Text
    , healthEndpoints :: Int
    , healthChecks    :: Int
    } deriving (Show, Generic)

instance ToJSON Health where
    toJSON h = object
        [ "status"    .= healthStatus h
        , "endpoints" .= healthEndpoints h
        , "checks"    .= healthChecks h
        ]
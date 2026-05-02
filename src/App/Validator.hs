{-# LANGUAGE OverloadedStrings #-}
module App.Validator where

import App.Contract
import Data.Aeson

-- Alias for validateContract
validate :: Value -> Value -> [ValidationError]
validate = validateContract

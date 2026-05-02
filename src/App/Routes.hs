{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}
module App.Routes where

import Servant
import Servant.HTML.Lucid
import Lucid (Html)
import App.Types

type API = 
       Get '[HTML] (Html ())
  :<|> "endpoints" :> Get '[HTML] (Html ())
  :<|> "api" :> "endpoints" :> Get '[JSON] [Endpoint]

api :: Proxy API
api = Proxy
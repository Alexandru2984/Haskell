{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}
module App.Routes where

import Servant
import Servant.HTML.Lucid
import Lucid (Html)
import Web.FormUrlEncoded (FromForm(..), parseUnique)
import qualified Data.Text as T
import Data.Aeson (Value, FromJSON(..), withObject, (.:))
import App.Types

data EndpointForm = EndpointForm
    { efName :: T.Text, efProject :: T.Text, efUrl :: T.Text, efMethod :: T.Text, efContract :: T.Text }
instance FromForm EndpointForm where
    fromForm f = EndpointForm <$> parseUnique "name" f <*> parseUnique "project" f <*> parseUnique "url" f <*> parseUnique "method" f <*> parseUnique "contract" f

data ValidationInput = ValidationInput { inputContract :: Value, inputResponse :: Value }
instance FromJSON ValidationInput where
    parseJSON = withObject "ValidationInput" $ \o -> ValidationInput <$> o .: "contract" <*> o .: "response"

type Redirect = Headers '[Header "Location" String] NoContent
type CSVDownload = Headers '[Header "Content-Disposition" String] T.Text

type API =
       QueryParam "hours" Int :> Get '[HTML] (Html ())
  :<|> "endpoints" :> Get '[HTML] (Html ())
  :<|> "endpoints" :> "new" :> Get '[HTML] (Html ())
  :<|> "endpoints" :> Capture "id" Int :> "edit" :> Get '[HTML] (Html ())
  :<|> "endpoints" :> "create" :> ReqBody '[FormUrlEncoded] EndpointForm :> Verb 'POST 303 '[HTML] Redirect
  :<|> "endpoints" :> Capture "id" Int :> "update" :> ReqBody '[FormUrlEncoded] EndpointForm :> Verb 'POST 303 '[HTML] Redirect
  :<|> "endpoints" :> Capture "id" Int :> "delete" :> Verb 'POST 303 '[HTML] Redirect
  :<|> "incidents" :> Get '[HTML] (Html ())
  :<|> "health" :> Get '[JSON] Health
  :<|> "metrics" :> Get '[PlainText] T.Text
  :<|> "api" :> "endpoints" :> Get '[JSON] [Endpoint]
  :<|> "endpoints" :> Capture "id" Int :> QueryParam "hours" Int :> Get '[HTML] (Html ())
  :<|> "endpoints" :> Capture "id" Int :> "toggle" :> Verb 'POST 303 '[HTML] Redirect
  :<|> "endpoints" :> Capture "id" Int :> "check" :> Verb 'POST 303 '[HTML] Redirect
  :<|> "endpoints" :> Capture "id" Int :> "export.csv" :> QueryParam "hours" Int :> Get '[PlainText] CSVDownload
  :<|> "playground" :> Get '[HTML] (Html ())
  :<|> "api" :> "validate" :> ReqBody '[JSON] ValidationInput :> Post '[JSON] Value

api :: Proxy API
api = Proxy

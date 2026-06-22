{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}
module App.Routes where

import Servant
import Servant.HTML.Lucid
import Lucid (Html)
import Web.FormUrlEncoded (FromForm(..), parseUnique)
import qualified Data.Text as T
import App.Types

-- | Submitted add/edit form.
data EndpointForm = EndpointForm
    { efName     :: T.Text
    , efProject  :: T.Text
    , efUrl      :: T.Text
    , efMethod   :: T.Text
    , efContract :: T.Text   -- raw JSON contract
    } deriving (Show)

instance FromForm EndpointForm where
    fromForm f = EndpointForm
        <$> parseUnique "name" f
        <*> parseUnique "project" f
        <*> parseUnique "url" f
        <*> parseUnique "method" f
        <*> parseUnique "contract" f

-- | A 303 redirect carrying a Location header (POST/redirect/GET).
type Redirect = Headers '[Header "Location" String] NoContent

type API =
       Get '[HTML] (Html ())
  :<|> "endpoints" :> Get '[HTML] (Html ())
  :<|> "endpoints" :> "new" :> Get '[HTML] (Html ())
  :<|> "endpoints" :> Capture "id" Int :> "edit" :> Get '[HTML] (Html ())
  :<|> "endpoints" :> "create"
        :> ReqBody '[FormUrlEncoded] EndpointForm :> Verb 'POST 303 '[HTML] Redirect
  :<|> "endpoints" :> Capture "id" Int :> "update"
        :> ReqBody '[FormUrlEncoded] EndpointForm :> Verb 'POST 303 '[HTML] Redirect
  :<|> "endpoints" :> Capture "id" Int :> "delete" :> Verb 'POST 303 '[HTML] Redirect
  :<|> "api" :> "endpoints" :> Get '[JSON] [Endpoint]

api :: Proxy API
api = Proxy

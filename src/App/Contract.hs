{-# LANGUAGE OverloadedStrings #-}
module App.Contract where

import Data.Aeson
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import qualified Data.Text as T
import qualified Data.Vector as V

data ValidationError = ValidationError
    { errorPath :: T.Text
    , errorMessage :: T.Text
    } deriving (Show, Eq)

instance ToJSON ValidationError where
    toJSON (ValidationError p m) = object [ "path" .= p, "message" .= m ]

instance FromJSON ValidationError where
    parseJSON = withObject "ValidationError" $ \v -> ValidationError
        <$> v .: "path"
        <*> v .: "message"

validateContract :: Value -> Value -> [ValidationError]
validateContract expected actual = validateNode "$" expected actual

validateNode :: T.Text -> Value -> Value -> [ValidationError]
validateNode path (Object e) (Object a) =
    let expectedType = KM.lookup "type" e
    in case expectedType of
        Just (String "object") -> validateObject path e a
        Just (String "array")  -> [ValidationError path "Expected array, got object"]
        Just (String "string") -> [ValidationError path "Expected string, got object"]
        Just (String "number") -> [ValidationError path "Expected number, got object"]
        Just (String "integer")-> [ValidationError path "Expected integer, got object"]
        Just (String "boolean")-> [ValidationError path "Expected boolean, got object"]
        Just (String "null")   -> [ValidationError path "Expected null, got object"]
        _ -> [] -- Unspecified type
validateNode path (Object e) actual =
    let expectedType = KM.lookup "type" e
    in case expectedType of
        Just (String "object") -> [ValidationError path ("Expected object, got " <> valueType actual)]
        Just (String "array") -> case actual of
            Array arr -> validateArray path e arr
            _ -> [ValidationError path ("Expected array, got " <> valueType actual)]
        Just (String "string") -> case actual of
            String _ -> []
            _ -> [ValidationError path ("Expected string, got " <> valueType actual)]
        Just (String "number") -> case actual of
            Number _ -> []
            _ -> [ValidationError path ("Expected number, got " <> valueType actual)]
        Just (String "integer") -> case actual of
            Number n -> [] -- Simplified, properly we should check if integer
            _ -> [ValidationError path ("Expected integer, got " <> valueType actual)]
        Just (String "boolean") -> case actual of
            Bool _ -> []
            _ -> [ValidationError path ("Expected boolean, got " <> valueType actual)]
        Just (String "null") -> case actual of
            Null -> []
            _ -> [ValidationError path ("Expected null, got " <> valueType actual)]
        _ -> []
validateNode _ _ _ = []

validateObject :: T.Text -> Object -> Object -> [ValidationError]
validateObject path expected actual = requiredErrors ++ optionalErrors ++ extraErrors
  where
    requiredFields = case KM.lookup "required" expected of
        Just (Object r) -> r
        _ -> KM.empty
    
    optionalFields = case KM.lookup "optional" expected of
        Just (Object o) -> o
        _ -> KM.empty
        
    allowExtra = case KM.lookup "allow_extra_fields" expected of
        Just (Bool b) -> b
        _ -> False
        
    requiredErrors = concatMap (\(k, v) -> 
        case KM.lookup k actual of
            Nothing -> [ValidationError (path <> "." <> K.toText k) "Missing required field"]
            Just actualVal -> validateNode (path <> "." <> K.toText k) v actualVal
        ) (KM.toList requiredFields)
        
    optionalErrors = concatMap (\(k, v) -> 
        case KM.lookup k actual of
            Nothing -> []
            Just actualVal -> validateNode (path <> "." <> K.toText k) v actualVal
        ) (KM.toList optionalFields)
        
    extraErrors = if allowExtra then [] else 
        let expectedKeys = KM.keys requiredFields ++ KM.keys optionalFields
            actualKeys = KM.keys actual
            extraKeys = filter (`notElem` expectedKeys) actualKeys
        in map (\k -> ValidationError (path <> "." <> K.toText k) "Extra field not allowed") extraKeys

validateArray :: T.Text -> Object -> V.Vector Value -> [ValidationError]
validateArray path expected arr = 
    case KM.lookup "items" expected of
        Just itemsContract -> concat $ zipWith (\idx val -> validateNode (path <> "[" <> T.pack (show idx) <> "]") itemsContract val) [0..] (V.toList arr)
        Nothing -> []

valueType :: Value -> T.Text
valueType (Object _) = "object"
valueType (Array _) = "array"
valueType (String _) = "string"
valueType (Number _) = "number"
valueType (Bool _) = "boolean"
valueType Null = "null"
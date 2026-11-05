{-# LANGUAGE OverloadedStrings #-}
module App.Contract where

import Data.Aeson
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import qualified Data.Text as T
import qualified Data.Vector as V
import Data.Scientific (isInteger)

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
validateNode path schema actual
    | Object node <- schema, Just (Bool True) <- KM.lookup "nullable" node, Null <- actual = []
    | otherwise = validateType path schema actual ++ constraints path schema actual

validateType :: T.Text -> Value -> Value -> [ValidationError]
validateType path (Object e) (Object a) =
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
validateType path (Object e) actual =
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
            Number n
                | isInteger n -> []
                | otherwise   -> [ValidationError path "Expected integer, got fractional number"]
            _ -> [ValidationError path ("Expected integer, got " <> valueType actual)]
        Just (String "boolean") -> case actual of
            Bool _ -> []
            _ -> [ValidationError path ("Expected boolean, got " <> valueType actual)]
        Just (String "null") -> case actual of
            Null -> []
            _ -> [ValidationError path ("Expected null, got " <> valueType actual)]
        _ -> []
validateType _ _ _ = []

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

constraints :: T.Text -> Value -> Value -> [ValidationError]
constraints path (Object node) value = enumErrors ++ boundsErrors
  where
    enumErrors = case KM.lookup "enum" node of
        Just (Array xs) | value `notElem` V.toList xs -> [ValidationError path "Value is not in the allowed enum"]
        _ -> []
    violation key predicate message = case KM.lookup key node of
        Just (Number n) | predicate n -> [ValidationError path message]
        _ -> []
    boundsErrors = case value of
        Number n -> violation "minimum" (n <) "Number is below minimum" ++ violation "maximum" (n >) "Number exceeds maximum"
        String t -> violation "min_length" (fromIntegral (T.length t) <) "String is too short" ++ violation "max_length" (fromIntegral (T.length t) >) "String is too long"
        _ -> []
constraints _ _ _ = []

-- Validate schema definitions as data; unknown types/keywords must never silently pass.
validateDefinition :: Value -> [ValidationError]
validateDefinition = go 0 "$"
  where
    go :: Int -> T.Text -> Value -> [ValidationError]
    go depth path (Object node)
        | depth > 20 = [ValidationError path "Contract nesting exceeds 20 levels"]
        | otherwise = typeErrors ++ keywordErrors ++ fieldErrors ++ itemErrors ++ optionErrors ++ overlapErrors
      where
        kind = KM.lookup "type" node
        typeErrors = [ValidationError path "A supported type is required" | kind `notElem` map (Just . String) ["object","array","string","number","integer","boolean","null"]]
        allowed = ["type","nullable","enum"] ++ case kind of
            Just (String "object") -> ["required","optional","allow_extra_fields"]
            Just (String "array") -> ["items"]
            Just (String "string") -> ["min_length","max_length"]
            Just (String "number") -> ["minimum","maximum"]
            Just (String "integer") -> ["minimum","maximum"]
            _ -> []
        keywordErrors = [ValidationError (path <> "." <> K.toText k) "Unknown contract keyword" | k <- KM.keys node, K.toText k `notElem` allowed]
        fieldErrors = concatMap fields ["required","optional"]
        fields key = case KM.lookup key node of
            Nothing -> []
            Just (Object properties)
                | KM.size properties <= 100 -> concat [go (depth+1) (path <> "." <> K.toText k) v | (k,v) <- KM.toList properties]
                | otherwise -> [ValidationError path "At most 100 fields are allowed per object"]
            _ -> [ValidationError path "Required and optional must be field-to-schema objects"]
        overlapErrors = case (KM.lookup "required" node, KM.lookup "optional" node) of
            (Just (Object required), Just (Object optional)) -> [ValidationError path "Required and optional fields overlap" | any (`KM.member` optional) (KM.keys required)]
            _ -> []
        itemErrors = maybe [] (go (depth+1) (path <> "[]")) (KM.lookup "items" node)
        optionErrors = concatMap boolean ["nullable","allow_extra_fields"] ++ enumCheck ++ numericCheck ++ orderCheck
        boolean key = case KM.lookup key node of
            Nothing -> []
            Just (Bool _) -> []
            _ -> [ValidationError path "Boolean contract option has invalid type"]
        enumCheck = case KM.lookup "enum" node of
            Nothing -> []
            Just (Array xs) | not (V.null xs) && V.length xs <= 50 -> []
            _ -> [ValidationError path "Enum must contain 1 to 50 values"]
        numericCheck = concatMap numeric ["minimum","maximum","min_length","max_length"]
        numeric key = case KM.lookup key node of
            Nothing -> []
            Just (Number n) | key `elem` ["minimum","maximum"] || (n >= 0 && isInteger n && n <= 1048576) -> []
            _ -> [ValidationError path "Invalid numeric constraint"]
        orderCheck = concatMap ordered [("minimum","maximum"),("min_length","max_length")]
        ordered (lo,hi) = case (KM.lookup lo node, KM.lookup hi node) of
            (Just (Number a), Just (Number b)) | a > b -> [ValidationError path "Minimum exceeds maximum"]
            _ -> []
    go _ path _ = [ValidationError path "Contract nodes must be objects"]

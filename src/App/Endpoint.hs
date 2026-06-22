{-# LANGUAGE OverloadedStrings #-}
module App.Endpoint where

import Control.Monad (void)
import Database.PostgreSQL.Simple
import App.Types
import Data.Aeson (Value)
import qualified Data.Text as T

endpointColumns :: Query
endpointColumns = "id, name, project, url, method, status, enabled, contract"

getEndpoints :: Connection -> IO [Endpoint]
getEndpoints conn =
    query_ conn ("SELECT " <> endpointColumns <> " FROM endpoints ORDER BY id DESC")

getEnabledEndpoints :: Connection -> IO [Endpoint]
getEnabledEndpoints conn =
    query_ conn ("SELECT " <> endpointColumns
                 <> " FROM endpoints WHERE enabled = true ORDER BY id")

getEndpointById :: Connection -> Int -> IO (Maybe Endpoint)
getEndpointById conn eid = do
    rows <- query conn
        ("SELECT " <> endpointColumns <> " FROM endpoints WHERE id = ?")
        (Only eid)
    return $ case rows of
        (e : _) -> Just e
        []      -> Nothing

createEndpoint :: Connection -> T.Text -> T.Text -> T.Text -> T.Text -> Value -> IO Int
createEndpoint conn name project url method contract = do
    rows <- query conn
        "INSERT INTO endpoints (name, project, url, method, status, enabled, contract) \
        \ VALUES (?, ?, ?, ?, 0, true, ?) RETURNING id"
        (name, project, url, method, contract)
    return $ case rows of
        (Only eid : _) -> eid
        []             -> 0

updateEndpoint :: Connection -> Int -> T.Text -> T.Text -> T.Text -> T.Text -> Value -> IO ()
updateEndpoint conn eid name project url method contract = void $ execute conn
    "UPDATE endpoints SET name = ?, project = ?, url = ?, method = ?, contract = ? \
    \ WHERE id = ?"
    (name, project, url, method, contract, eid)

deleteEndpoint :: Connection -> Int -> IO ()
deleteEndpoint conn eid =
    void $ execute conn "DELETE FROM endpoints WHERE id = ?" (Only eid)

-- | Persisted health: 1 = passing, -1 = failing, 0 = unknown.
setEndpointStatus :: Connection -> Int -> Int -> IO ()
setEndpointStatus conn eid st =
    void $ execute conn "UPDATE endpoints SET status = ? WHERE id = ?" (st, eid)

insertSample :: Connection -> IO ()
insertSample conn = do
    let contractStr = "{\"type\": \"object\", \"required\": {\"status\": {\"type\": \"string\"}}, \"allow_extra_fields\": true}" :: String
    _ <- execute conn
        "INSERT INTO endpoints (name, project, url, method, status, enabled, contract) VALUES (?, ?, ?, ?, ?, ?, ?)"
        ("Sample API" :: String, "Demo" :: String, "https://haskell.micutu.com" :: String, "GET" :: String, 0 :: Int, True :: Bool, contractStr)
    return ()

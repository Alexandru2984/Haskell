{-# LANGUAGE OverloadedStrings #-}
module App.Endpoint where

import Control.Monad (void)
import Database.PostgreSQL.Simple
import App.Types
import Data.Aeson (Value)
import qualified Data.Text as T

endpointColumns :: Query
endpointColumns = "id, name, project, url, method, status, enabled, contract, revision"

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
    "UPDATE endpoints SET name = ?, project = ?, url = ?, method = ?, contract = ?, status = 0, revision = revision + 1 \
    \ WHERE id = ?"
    (name, project, url, method, contract, eid)

deleteEndpoint :: Connection -> Int -> IO ()
deleteEndpoint conn eid =
    void $ execute conn "DELETE FROM endpoints WHERE id = ?" (Only eid)

-- | Persist the latest health of an endpoint.
setEndpointStatus :: Connection -> Int -> Status -> IO ()
setEndpointStatus conn eid st =
    void $ execute conn "UPDATE endpoints SET status = ? WHERE id = ?" (st, eid)

-- Serialize quota checks with inserts; concurrent submissions cannot bypass the cap.
createEndpointLimited :: Connection -> Int -> T.Text -> T.Text -> T.Text -> T.Text -> Value -> IO (Maybe Int)
createEndpointLimited conn limit name project url method contract = withTransaction conn $ do
    _ <- execute_ conn "LOCK TABLE endpoints IN SHARE ROW EXCLUSIVE MODE"
    [Only count] <- query_ conn "SELECT count(*)::int FROM endpoints"
    if count >= limit then pure Nothing
    else Just <$> createEndpoint conn name project url method contract

toggleEndpoint :: Connection -> Int -> IO ()
toggleEndpoint conn eid = void $ execute conn
    "UPDATE endpoints SET enabled = NOT enabled, status = 0, revision = revision + 1 WHERE id = ?" (Only eid)

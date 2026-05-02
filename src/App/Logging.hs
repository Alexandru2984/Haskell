{-# LANGUAGE OverloadedStrings #-}
module App.Logging where

import Control.Monad (when)
import Data.Time (getCurrentTime)

logInfo :: String -> IO ()
logInfo msg = do
    now <- getCurrentTime
    putStrLn $ "[INFO] " ++ show now ++ " - " ++ msg

logError :: String -> IO ()
logError msg = do
    now <- getCurrentTime
    putStrLn $ "[ERROR] " ++ show now ++ " - " ++ msg
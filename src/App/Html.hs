{-# LANGUAGE OverloadedStrings #-}
module App.Html where

import Lucid
import App.Types

dashboardHtml :: [Endpoint] -> Html ()
dashboardHtml endpoints = html_ $ do
    head_ $ do
        title_ "Haskell API Monitor"
        style_ "body { background: #111; color: #eee; font-family: sans-serif; }"
    body_ $ do
        h1_ "API Contract Monitor"
        p_ "System is running."
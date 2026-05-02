{-# LANGUAGE OverloadedStrings #-}
module App.Html where

import Lucid
import App.Types
import qualified Data.Text as T

layout :: Html () -> Html ()
layout content = html_ $ do
    head_ $ do
        title_ "Haskell API Monitor"
        meta_ [charset_ "utf-8"]
        meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
        script_ [src_ "https://unpkg.com/htmx.org@1.9.12"] ("" :: T.Text)
        style_ css
    body_ $ do
        div_ [class_ "sidebar"] $ do
            h1_ "API Monitor"
            a_ [href_ "/", class_ "nav-item"] "Dashboard"
            a_ [href_ "/endpoints", class_ "nav-item"] "Endpoints"
            a_ [href_ "/incidents", class_ "nav-item"] "Incidents"
        
        div_ [class_ "main-content"] content

css :: T.Text
css = "body { margin: 0; font-family: system-ui, sans-serif; background: #0f172a; color: #f3f4f6; display: flex; height: 100vh; overflow: hidden; }\n\
      \.sidebar { width: 250px; background: #1e293b; padding: 1.5rem; display: flex; flex-direction: column; border-right: 1px solid #334155; }\n\
      \.sidebar h1 { font-size: 1.25rem; color: #38bdf8; margin-bottom: 2rem; display: flex; align-items: center; gap: 0.5rem; }\n\
      \.nav-item { display: block; padding: 0.75rem 1rem; color: #cbd5e1; text-decoration: none; border-radius: 0.375rem; margin-bottom: 0.5rem; transition: background 0.2s; cursor: pointer; }\n\
      \.nav-item:hover { background: #334155; color: #fff; }\n\
      \.main-content { flex: 1; padding: 2rem; overflow-y: auto; }\n\
      \.header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; }\n\
      \.card-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1.5rem; margin-bottom: 2.5rem; }\n\
      \.card { background: #1e293b; padding: 1.5rem; border-radius: 0.5rem; border: 1px solid #334155; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1); }\n\
      \.card-title { font-size: 0.875rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.5rem; }\n\
      \.card-value { font-size: 2.25rem; font-weight: bold; color: #f8fafc; }\n\
      \.table-container { background: #1e293b; border-radius: 0.5rem; border: 1px solid #334155; overflow: auto; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1); }\n\
      \table { width: 100%; border-collapse: collapse; text-align: left; }\n\
      \th, td { padding: 1rem 1.5rem; border-bottom: 1px solid #334155; }\n\
      \th { background: #0f172a; font-weight: 600; color: #94a3b8; font-size: 0.875rem; text-transform: uppercase; }\n\
      \tr:last-child td { border-bottom: none; }\n\
      \.status-badge { padding: 0.25rem 0.75rem; border-radius: 9999px; font-size: 0.75rem; font-weight: 600; display: inline-block; }\n\
      \.status-ok { background: rgba(16, 185, 129, 0.2); color: #34d399; }\n\
      \.status-fail { background: rgba(239, 68, 68, 0.2); color: #f87171; }\n\
      \.status-unknown { background: rgba(148, 163, 184, 0.2); color: #cbd5e1; }\n\
      \.btn { background: #0ea5e9; color: white; border: none; padding: 0.5rem 1rem; border-radius: 0.375rem; cursor: pointer; font-weight: 500; transition: background 0.2s; text-decoration: none; }\n\
      \.btn:hover { background: #0284c7; }"

dashboardHtml :: [Endpoint] -> Html ()
dashboardHtml endpoints = layout $ do
    div_ [class_ "header"] $ do
        h2_ "Dashboard Overview"
        a_ [href_ "/endpoints/new", class_ "btn"] "+ Add Endpoint"
    
    div_ [class_ "card-grid"] $ do
        div_ [class_ "card"] $ do
            div_ [class_ "card-title"] "Total Monitored"
            div_ [class_ "card-value"] (toHtml $ show $ length endpoints)
        div_ [class_ "card"] $ do
            div_ [class_ "card-title"] "Healthy"
            div_ [class_ "card-value", style_ "color: #34d399;"] (toHtml $ show $ length (filter (\e -> endpointStatus e == 1) endpoints))
        div_ [class_ "card"] $ do
            div_ [class_ "card-title"] "Failing"
            div_ [class_ "card-value", style_ "color: #f87171;"] (toHtml $ show $ length (filter (\e -> endpointStatus e == (-1)) endpoints))

    h3_ [style_ "margin-bottom: 1rem;"] "Recent Endpoints"
    endpointsTable endpoints

endpointsHtml :: [Endpoint] -> Html ()
endpointsHtml endpoints = layout $ do
    div_ [class_ "header"] $ do
        h2_ "All Monitored Endpoints"
        a_ [href_ "/endpoints/new", class_ "btn"] "+ Add Endpoint"
    endpointsTable endpoints

endpointsTable :: [Endpoint] -> Html ()
endpointsTable [] = p_ [style_ "color: #94a3b8;"] "No endpoints configured yet. Add your first API endpoint to begin monitoring."
endpointsTable endpoints = div_ [class_ "table-container"] $ do
    table_ $ do
        thead_ $ tr_ $ do
            th_ "Name"
            th_ "Project"
            th_ "URL"
            th_ "Method"
            th_ "Status"
            th_ "Actions"
        tbody_ $ mapM_ renderEndpointRow endpoints

renderEndpointRow :: Endpoint -> Html ()
renderEndpointRow e = tr_ $ do
    td_ (toHtml $ endpointName e)
    td_ (toHtml $ endpointProject e)
    td_ [style_ "color: #94a3b8; font-family: monospace; font-size: 0.9em;"] (toHtml $ endpointUrl e)
    td_ (toHtml $ endpointMethod e)
    td_ $ do
        case endpointStatus e of
            1    -> span_ [class_ "status-badge status-ok"] "Passing"
            (-1) -> span_ [class_ "status-badge status-fail"] "Failing"
            _    -> span_ [class_ "status-badge status-unknown"] "Unknown"
    td_ $ do
        button_ [class_ "btn", style_ "background: #475569; padding: 0.25rem 0.5rem; font-size: 0.75rem;"] "Edit"

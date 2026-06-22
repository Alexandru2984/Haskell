{-# LANGUAGE OverloadedStrings #-}
module App.Html where

import Lucid
import App.Types
import Data.Aeson (encode, Value)
import Data.Time (UTCTime)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE

layout :: Html () -> Html ()
layout content = html_ $ do
    head_ $ do
        title_ "Haskell API Monitor"
        meta_ [charset_ "utf-8"]
        meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
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
      \.btn { background: #0ea5e9; color: white; border: none; padding: 0.5rem 1rem; border-radius: 0.375rem; cursor: pointer; font-weight: 500; transition: background 0.2s; text-decoration: none; display: inline-block; }\n\
      \.btn:hover { background: #0284c7; }\n\
      \.btn-sm { padding: 0.25rem 0.6rem; font-size: 0.75rem; }\n\
      \.btn-secondary { background: #475569; }\n\
      \.btn-secondary:hover { background: #334155; }\n\
      \.btn-danger { background: #b91c1c; }\n\
      \.btn-danger:hover { background: #991b1b; }\n\
      \form.card-form { background: #1e293b; padding: 1.5rem; border-radius: 0.5rem; border: 1px solid #334155; max-width: 640px; }\n\
      \.form-row { display: flex; flex-direction: column; margin-bottom: 1rem; }\n\
      \.form-row label { font-size: 0.8rem; color: #94a3b8; margin-bottom: 0.35rem; text-transform: uppercase; letter-spacing: 0.03em; }\n\
      \.form-row input, .form-row select, .form-row textarea { background: #0f172a; border: 1px solid #334155; color: #f3f4f6; padding: 0.6rem 0.75rem; border-radius: 0.375rem; font-size: 0.95rem; font-family: inherit; }\n\
      \.form-row textarea { min-height: 140px; font-family: monospace; }\n\
      \.inline-form { display: inline; }"

-- | Dashboard. The triple is (total checks, passed checks, avg latency ms).
dashboardHtml :: [Endpoint] -> (Int, Int, Maybe Double) -> Html ()
dashboardHtml endpoints (totalChecks, passedChecks, avgLatency) = layout $ do
    div_ [class_ "header"] $ do
        h2_ "Dashboard Overview"
        a_ [href_ "/endpoints/new", class_ "btn"] "+ Add Endpoint"

    div_ [class_ "card-grid"] $ do
        statCard "Total Monitored" (T.pack (show (length endpoints))) Nothing
        statCard "Healthy"  (T.pack (show healthy)) (Just "#34d399")
        statCard "Failing"  (T.pack (show failing)) (Just "#f87171")
        statCard "Uptime"   uptimeStr  (Just "#38bdf8")
        statCard "Avg Latency" latencyStr Nothing

    h3_ [style_ "margin-bottom: 1rem;"] "Recent Endpoints"
    endpointsTable endpoints
  where
    healthy = length (filter (\e -> endpointStatus e == Passing) endpoints)
    failing = length (filter (\e -> endpointStatus e == Failing) endpoints)
    uptimeStr
        | totalChecks == 0 = "—"
        | otherwise =
            T.pack (show (round (100 * fromIntegral passedChecks
                                     / fromIntegral totalChecks :: Double) :: Int)) <> "%"
    latencyStr = case avgLatency of
        Nothing -> "—"
        Just l  -> T.pack (show (round l :: Int)) <> " ms"

statCard :: T.Text -> T.Text -> Maybe T.Text -> Html ()
statCard title val mColor = div_ [class_ "card"] $ do
    div_ [class_ "card-title"] (toHtml title)
    case mColor of
        Just c  -> div_ [class_ "card-value", style_ ("color: " <> c <> ";")] (toHtml val)
        Nothing -> div_ [class_ "card-value"] (toHtml val)

-- | Incident feed: rows are (name, url, status, latency_ms, time, errors).
incidentsHtml :: [(T.Text, T.Text, Int, Int, UTCTime, Value)] -> Html ()
incidentsHtml [] = layout $ do
    div_ [class_ "header"] $ h2_ "Incidents"
    p_ [style_ "color: #94a3b8;"] "No incidents recorded. All checks have passed so far."
incidentsHtml rows = layout $ do
    div_ [class_ "header"] $ h2_ "Incidents"
    div_ [class_ "table-container"] $ table_ $ do
        thead_ $ tr_ $ do
            th_ "Endpoint"
            th_ "URL"
            th_ "Status"
            th_ "Latency"
            th_ "When"
            th_ "Errors"
        tbody_ $ mapM_ incidentRow rows

incidentRow :: (T.Text, T.Text, Int, Int, UTCTime, Value) -> Html ()
incidentRow (name, url, status, latency, time, errs) = tr_ $ do
    td_ (toHtml name)
    td_ [style_ "color: #94a3b8; font-family: monospace; font-size: 0.85em;"] (toHtml url)
    td_ $ span_ [class_ "status-badge status-fail"] (toHtml (T.pack (show status)))
    td_ (toHtml (T.pack (show latency) <> " ms"))
    td_ [style_ "color: #94a3b8;"] (toHtml (T.pack (show time)))
    td_ [style_ "font-family: monospace; font-size: 0.8em; color: #f87171;"]
        (toHtml (valueToText errs))

valueToText :: Value -> T.Text
valueToText = TL.toStrict . TLE.decodeUtf8 . encode

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
            Passing -> span_ [class_ "status-badge status-ok"] "Passing"
            Failing -> span_ [class_ "status-badge status-fail"] "Failing"
            Unknown -> span_ [class_ "status-badge status-unknown"] "Unknown"
    td_ $ do
        let eid = T.pack (show (endpointId e))
        a_ [href_ ("/endpoints/" <> eid <> "/edit"), class_ "btn btn-sm btn-secondary"] "Edit"
        form_ [ method_ "post", action_ ("/endpoints/" <> eid <> "/delete")
              , class_ "inline-form", style_ "margin-left: 0.5rem;"
              , onsubmit_ "return confirm('Delete this endpoint?');" ] $
            button_ [type_ "submit", class_ "btn btn-sm btn-danger"] "Delete"

-- | Add / edit endpoint form. 'Nothing' renders a blank create form.
endpointFormPage :: Maybe Endpoint -> Html ()
endpointFormPage mep = layout $ do
    div_ [class_ "header"] $
        h2_ (toHtml title)
    form_ [method_ "post", action_ action, class_ "card-form"] $ do
        textField  "Name"    "name"    (maybe "" endpointName mep)
        textField  "Project" "project" (maybe "" endpointProject mep)
        textField  "URL"     "url"     (maybe "" endpointUrl mep)
        methodField (maybe "GET" endpointMethod mep)
        contractField (maybe "{\n  \"type\": \"object\",\n  \"allow_extra_fields\": true\n}"
                             (TL.toStrict . TLE.decodeUtf8 . encode . endpointContract) mep)
        div_ [class_ "form-row"] $ do
            button_ [type_ "submit", class_ "btn"] (toHtml saveLabel)
            a_ [href_ "/endpoints", class_ "btn btn-secondary", style_ "margin-left: 0.5rem;"] "Cancel"
  where
    title     = maybe "Add Endpoint" (const "Edit Endpoint") mep :: T.Text
    saveLabel = maybe "Create" (const "Save changes") mep :: T.Text
    action    = case mep of
        Just e  -> "/endpoints/" <> T.pack (show (endpointId e)) <> "/update"
        Nothing -> "/endpoints/create"

textField :: T.Text -> T.Text -> T.Text -> Html ()
textField label name val = div_ [class_ "form-row"] $ do
    label_ (toHtml label)
    input_ [type_ "text", name_ name, value_ val, required_ "required"]

methodField :: T.Text -> Html ()
methodField current = div_ [class_ "form-row"] $ do
    label_ "Method"
    select_ [name_ "method"] $
        mapM_ (\m -> if m == current
                        then option_ [value_ m, selected_ "selected"] (toHtml m)
                        else option_ [value_ m] (toHtml m))
              ["GET", "POST", "PUT", "DELETE", "HEAD", "PATCH"]

contractField :: T.Text -> Html ()
contractField val = div_ [class_ "form-row"] $ do
    label_ "Contract (JSON)"
    textarea_ [name_ "contract"] (toHtml val)

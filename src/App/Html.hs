{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
module App.Html where

import Lucid
import Lucid.Base (makeAttribute)
import App.Types
import Data.Aeson (encode, Value)
import Data.List (nub, sort)
import Data.Time (UTCTime, formatTime, defaultTimeLocale)
import Numeric (showFFloat)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE

text :: Show a => a -> T.Text
text = T.pack . show
attr :: T.Text -> T.Text -> Attribute
attr = makeAttribute

layout :: T.Text -> T.Text -> Html () -> Html ()
layout active title content = do
    doctype_
    html_ [lang_ "en"] $ do
        head_ $ do
            meta_ [charset_ "utf-8"]
            meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
            title_ (toHtml (title <> " · Haskell Pulse"))
            meta_ [name_ "description", content_ "Monitor API availability, response times and JSON contracts with Haskell Pulse. Inspect incidents and catch schema drift before it reaches your users."]
            meta_ [name_ "robots", content_ "noindex, nofollow"]
            meta_ [name_ "theme-color", content_ "#101b31"]
            link_ [rel_ "icon", href_ "/assets/favicon.svg", type_ "image/svg+xml"]
            link_ [rel_ "stylesheet", href_ "/assets/app.css"]
            script_ [src_ "/assets/app.js", defer_ "defer"] ("" :: T.Text)
        body_ $ do
            a_ [class_ "skip-link", href_ "#main"] "Skip to content"
            aside_ [class_ "sidebar"] $ do
                a_ [href_ "/", class_ "brand", attr "aria-label" "Haskell Pulse home"] $ do
                    span_ [class_ "brand-mark", attr "aria-hidden" "true"] "λ"
                    span_ $ do "pulse"; small_ "HASKELL OBSERVATORY"
                div_ [class_ "nav-label"] "WORKSPACE"
                nav_ [attr "aria-label" "Main navigation"] $ do
                    navItem "overview" "/" "◫" "Overview"
                    navItem "monitors" "/endpoints" "◎" "Monitors"
                    navItem "incidents" "/incidents" "ϟ" "Incidents"
                    navItem "playground" "/playground" "⌘" "Playground"
                div_ [class_ "sidebar-foot"] $ do
                    strong_ "Built for the details."
                    p_ "Typed contracts. Clear signals."
                    p_ "Haskell · PostgreSQL"
            main_ [id_ "main", class_ "main-content"] $ do
                div_ [class_ "topbar"] $ do
                    div_ [class_ "breadcrumb"] $ do "Workspace / "; span_ (toHtml title)
                    div_ [class_ "top-actions"] $ do
                        span_ [class_ "live"] $ do span_ [class_ "dot"] ""; "Private workspace"
                        button_ [id_ "theme-toggle", class_ "btn btn-ghost btn-sm", type_ "button", attr "aria-label" "Toggle light and dark theme"] "◐ Theme"
                content
                footer_ [class_ "page-footer"] $ do
                    span_ "Haskell Pulse / API contract observatory"
                    span_ "Private monitoring · Times shown in your timezone"
  where
    navItem :: T.Text -> T.Text -> T.Text -> T.Text -> Html ()
    navItem key target icon label = a_ ([href_ target,class_ "nav-item"] ++ [attr "aria-current" "page" | active == key]) $ do
        span_ [class_ "nav-icon", attr "aria-hidden" "true"] (toHtml (icon :: T.Text))
        toHtml (label :: T.Text)

pageHeader :: T.Text -> T.Text -> T.Text -> Html () -> Html ()
pageHeader eyebrow title subtitle actions = div_ [class_ "header"] $ do
    div_ $ do p_ [class_ "eyebrow"] (toHtml eyebrow); h1_ (toHtml title); p_ [class_ "subtitle"] (toHtml subtitle)
    div_ [class_ "actions"] actions

addButton :: Html ()
addButton = a_ [href_ "/endpoints/new",class_ "btn"] "+ Add monitor"

periodPicker :: T.Text -> Int -> Html ()
periodPicker path hours = div_ [class_ "periods", attr "aria-label" "Statistics period"] $
    mapM_ (\(n,label) -> a_ [href_ (path <> "?hours=" <> text n),attr "aria-current" (if hours == n then "true" else "false")] (toHtml (label :: T.Text))) [(24,"24 hours"),(168,"7 days"),(720,"30 days")]

uptime :: Summary -> T.Text
uptime summary | summaryTotal summary == 0 = "—"
               | otherwise = T.pack (showFFloat (Just 2) (100 * fromIntegral (summaryPassed summary) / fromIntegral (summaryTotal summary) :: Double) "") <> "%"
latencyText :: Maybe Double -> T.Text
latencyText = maybe "—" (\n -> text (round n :: Int) <> " ms")

statCard :: T.Text -> T.Text -> T.Text -> Html ()
statCard title value note = div_ [class_ "card"] $ do
    p_ [class_ "card-title"] (toHtml title)
    p_ [class_ "card-value"] (toHtml value)
    p_ [class_ "card-note"] (toHtml note)

dashboardHtml :: [Endpoint] -> Summary -> [CheckResult] -> [(T.Text,T.Text,Int,Int,UTCTime,Value)] -> Int -> Html ()
dashboardHtml endpoints summary history incidents hours = layout "overview" "Overview" $ do
    pageHeader "THE BIG PICTURE" "Your APIs, at a glance." "Availability, performance, and contract health. One clear view." $ do
        label_ [class_ "refresh-label"] $ do input_ [id_ "auto-refresh",type_ "checkbox"]; "Refresh every minute"
        addButton
    div_ [class_ "card-grid"] $ do
        statCard "Monitors" (text (length endpoints)) (text enabled <> " active · " <> text (length endpoints-enabled) <> " paused")
        statCard "Availability" (uptime summary) "Successful checks in this period"
        statCard "Average response" (latencyText (summaryAverage summary)) "All completed checks in this period"
        statCard "P95 response" (latencyText (summaryP95 summary)) "95% of checks completed within this time"
    div_ [class_ "split"] $ do
        div_ [class_ "panel"] $ do
            div_ [class_ "panel-head"] $ do
                div_ $ do h2_ "Response time"; p_ (toHtml (text (summaryTotal summary) <> " checks in the selected period"))
                periodPicker "/" hours
            div_ [class_ "panel-body"] $ do
                latencyChart history
                p_ [class_ "footnote"] "Latest 60 checks, ordered from oldest to newest."
        div_ [class_ "panel"] $ do
            div_ [class_ "panel-head"] $ h2_ "Monitor health"
            div_ [class_ "panel-body"] $ do
                div_ [class_ "health-list"] $ do
                    healthLine "Passing" passing "positive"
                    healthLine "Needs attention" failing "negative"
                    healthLine "Pending / paused" (length endpoints-passing-failing) "muted"
                div_ [class_ "health-track",attr "role" "img",attr "aria-label" "Endpoint health distribution"] $
                    mapM_ (\e -> span_ [class_ ("health-segment " <> if not (endpointEnabled e) then "paused" else if endpointStatus e == Passing then "ok" else if endpointStatus e == Failing then "fail" else "")] "") endpoints
                p_ [class_ "footnote"] "Current state from the latest persisted check. Paused monitors do not run checks."
    div_ [class_ "panel"] $ do
        div_ [class_ "panel-head"] $ do
            div_ $ do h2_ "Your monitors"; p_ "Track availability and detect unexpected contract changes."
            a_ [href_ "/endpoints",class_ "btn btn-secondary btn-sm"] "View all monitors →"
        endpointsTable (take 8 endpoints)
    div_ [class_ "panel"] $ do
        div_ [class_ "panel-head"] $ do h2_ "Recent failed checks"; a_ [href_ "/incidents"] "View incidents →"
        div_ [class_ "panel-body"] $ if null incidents then p_ [class_ "muted"] "No failed checks have been recorded. Your next checks will appear here if they fail." else mapM_ incidentPreview (take 3 incidents)
  where
    enabled = length (filter endpointEnabled endpoints)
    passing = length (filter (\e -> endpointEnabled e && endpointStatus e == Passing) endpoints)
    failing = length (filter (\e -> endpointEnabled e && endpointStatus e == Failing) endpoints)
    healthLine :: T.Text -> Int -> T.Text -> Html ()
    healthLine label count tone = div_ [class_ "health-line"] $ do span_ (toHtml (label :: T.Text)); span_ [class_ ("health-number " <> tone)] (toHtml (text count))

endpointsHtml :: [Endpoint] -> Html ()
endpointsHtml endpoints = layout "monitors" "Monitors" $ do
    pageHeader "MONITORING" "Every endpoint. In view." "Search your APIs, review their health, and keep contracts in check." addButton
    div_ [class_ "panel"] $ do
        div_ [class_ "toolbar"] $ do
            label_ [for_ "monitor-search",class_ "search"] $ input_ [id_ "monitor-search",type_ "search",class_ "input search",placeholder_ "Search name, URL or project…  /",attr "aria-label" "Search monitors"]
            select_ [id_ "project-filter",attr "aria-label" "Filter by project"] $ do
                option_ [value_ ""] "All projects"
                mapM_ (\p -> option_ [value_ p] (toHtml p)) (sort (nub (map endpointProject endpoints)))
            select_ [id_ "status-filter",attr "aria-label" "Filter by status"] $ mapM_ (\(v,l) -> option_ [value_ v] (toHtml (l :: T.Text))) [("","All states"),("passing","Passing"),("failing","Failing"),("unknown","Pending"),("paused","Paused")]
            span_ [id_ "filter-count",class_ "filter-count",attr "aria-live" "polite"] (toHtml (text (length endpoints) <> " monitors"))
        endpointsTable endpoints
        div_ [id_ "filter-empty",class_ "empty",hidden_ "hidden"] "No monitors match these filters. Try another search."

endpointsTable :: [Endpoint] -> Html ()
endpointsTable [] = div_ [class_ "empty"] $ do
    strong_ "Start with your first API."
    p_ "Add a public endpoint and a JSON contract. Pulse will check its response and record the results automatically."
    addButton
endpointsTable endpoints = div_ [class_ "table-container"] $ table_ [class_ "monitors-table"] $ do
    caption_ [class_ "sr-only"] "Monitored endpoints and latest health"
    thead_ $ tr_ $ mapM_ (\x -> th_ [scope_ "col"] (toHtml (x :: T.Text))) ["Endpoint","Project","State","Monitoring","Manage"]
    tbody_ $ mapM_ renderEndpointRow endpoints

stateKey :: Endpoint -> T.Text
stateKey e | not (endpointEnabled e) = "paused"
           | endpointStatus e == Passing = "passing"
           | endpointStatus e == Failing = "failing"
           | otherwise = "unknown"
statusBadge :: Endpoint -> Html ()
statusBadge e = span_ [class_ ("status-badge " <> cls)] $ do span_ [class_ "dot"] ""; toHtml label
  where
    (cls,label) = case stateKey e of
        "passing" -> ("status-ok","Passing" :: T.Text)
        "failing" -> ("status-fail","Failing")
        "paused" -> ("status-unknown","Paused")
        _ -> ("status-unknown","Pending")
endpointPath :: Endpoint -> T.Text
endpointPath e = "/endpoints/" <> text (endpointId e)

renderEndpointRow :: Endpoint -> Html ()
renderEndpointRow e = tr_ [attr "data-monitor" "",attr "data-search" (T.toLower (T.unwords [endpointName e,endpointProject e,endpointUrl e])),attr "data-project" (endpointProject e),attr "data-status" (stateKey e)] $ do
    td_ $ do a_ [href_ (endpointPath e),class_ "endpoint-title"] (toHtml (endpointName e)); span_ [class_ "endpoint-url mono",title_ (endpointUrl e)] (toHtml (endpointUrl e))
    td_ (toHtml (endpointProject e))
    td_ (statusBadge e)
    td_ $ do span_ [class_ "method"] (toHtml (endpointMethod e)); span_ [class_ "muted"] (if endpointEnabled e then "Active" else "Paused")
    td_ $ a_ [href_ (endpointPath e),class_ "btn btn-secondary btn-sm"] "Details →"

endpointFormPage :: Maybe Endpoint -> Html ()
endpointFormPage current = layout "monitors" title $ do
    pageHeader "MONITOR CONFIGURATION" title "Define what a healthy API response should look like." (a_ [href_ "/endpoints",class_ "btn btn-secondary"] "← Monitors")
    div_ [class_ "form-grid"] $ do
        form_ [method_ "post",action_ target,class_ "card-form"] $ do
            textField "Monitor name" "name" "e.g. Production health" (maybe "" endpointName current) "text" "120"
            textField "Project" "project" "e.g. Storefront" (maybe "" endpointProject current) "text" "120"
            div_ [class_ "form-two"] $ do
                textField "Endpoint URL" "url" "https://api.example.com/health" (maybe "" endpointUrl current) "url" "2048"
                div_ [class_ "form-row"] $ do
                    label_ [for_ "method"] "HTTP method"
                    select_ [id_ "method",name_ "method"] $ mapM_ (\m -> option_ ([value_ m] ++ [selected_ "selected" | maybe "GET" endpointMethod current == m]) (toHtml m)) ["GET","HEAD"]
            div_ [class_ "form-row"] $ do
                label_ [for_ "contract"] "Response contract (JSON)"
                textarea_ [id_ "contract",name_ "contract",required_ "required",maxlength_ "32768",spellcheck_ "false"] (toHtml (maybe defaultContract (valueToText . endpointContract) current))
                small_ "GET validates JSON and the contract. HEAD checks HTTP availability only."
            div_ [class_ "actions"] $ do
                button_ [type_ "submit",class_ "btn"] (if maybe True (const False) current then "Create monitor" else "Save changes")
                button_ [type_ "button",class_ "btn btn-secondary",attr "data-format" "contract"] "Format JSON"
                a_ [href_ "/endpoints",class_ "btn btn-ghost"] "Cancel"
        aside_ $ do
            div_ [class_ "panel"] $ do
                div_ [class_ "panel-head"] $ h2_ "A contract you can trust"
                div_ [class_ "panel-body"] $ do
                    p_ [class_ "muted"] "Start with a simple contract, then add the fields that matter."
                    ul_ [class_ "help-list"] $ do
                        li_ "required / optional map field names to nested contracts."
                        li_ "Use enum, nullable, minimum/maximum or min_length/max_length for stronger checks."
                        li_ "allow_extra_fields defaults to false."
                        li_ "Monitoring sends read-only GET or HEAD requests to public IPv4-reachable URLs."
                    a_ [href_ "/playground",class_ "btn btn-secondary"] "Try the playground →"
            div_ [class_ "callout"] "Keep tokens and passwords out of URLs. Private-network targets, redirects and URL credentials are blocked."
  where
    title = maybe "Add a monitor" (const "Edit monitor") current
    target = maybe "/endpoints/create" (\e -> endpointPath e <> "/update") current

textField :: T.Text -> T.Text -> T.Text -> T.Text -> T.Text -> T.Text -> Html ()
textField label name hint val kind limit = div_ [class_ "form-row"] $ do
    label_ [for_ name] (toHtml label)
    input_ [id_ name,type_ kind,name_ name,value_ val,placeholder_ hint,required_ "required",maxlength_ limit]

defaultContract :: T.Text
defaultContract = "{\n  \"type\": \"object\",\n  \"required\": {\n    \"status\": {\"type\": \"string\"}\n  },\n  \"allow_extra_fields\": true\n}"

endpointDetailHtml :: Endpoint -> Summary -> [CheckResult] -> Int -> Html ()
endpointDetailHtml endpoint summary history hours = layout "monitors" (endpointName endpoint) $ do
    pageHeader (endpointProject endpoint) (endpointName endpoint) "Inspect response history and manage this monitor." $ do
        a_ [href_ (path <> "/edit"),class_ "btn btn-secondary"] "Edit monitor"
        form_ [method_ "post",action_ (path <> "/check"),class_ "inline-form"] $ button_ ([type_ "submit",class_ "btn"] ++ [disabled_ "disabled" | not (endpointEnabled endpoint)]) "↻ Check now"
    div_ [class_ "actions"] $ do
        statusBadge endpoint
        span_ [class_ "method"] (toHtml (endpointMethod endpoint))
        span_ [class_ "detail-url mono"] (toHtml (endpointUrl endpoint))
        button_ [class_ "btn btn-ghost btn-sm",type_ "button",attr "data-copy" (endpointUrl endpoint)] "Copy URL"
    p_ [class_ "footnote"] "Checks run on the configured server interval. Manual checks share the same concurrency limit and have a 5-second global cooldown."
    div_ [class_ "panel-head"] $ do p_ [class_ "window-label"] "Metrics window"; periodPicker path hours
    div_ [class_ "card-grid"] $ do
        statCard "Availability" (uptime summary) "Successful checks in this period"
        statCard "Checks recorded" (text (summaryTotal summary)) "Completed checks in this period"
        statCard "Average response" (latencyText (summaryAverage summary)) "Includes failing checks"
        statCard "P95 response" (latencyText (summaryP95 summary)) "95th percentile latency"
    div_ [class_ "panel"] $ do
        div_ [class_ "panel-head"] $ h2_ "Availability timeline"
        div_ [class_ "panel-body"] $ do
            if null history then p_ [class_ "muted"] "No checks in this period. Run a check or wait for the scheduler."
            else do
                div_ [class_ "uptime-strip",attr "role" "img",attr "aria-label" "Recent check results, oldest to newest"] $ mapM_ tick (reverse (take 60 history))
                div_ [class_ "strip-labels"] $ do span_ "Oldest check"; span_ "Latest check"
            latencyChart (take 60 history)
    div_ [class_ "panel"] $ do
        div_ [class_ "panel-head"] $ do h2_ "Check history"; a_ [href_ (path <> "/export.csv?hours=" <> text hours),class_ "btn btn-secondary btn-sm"] "↓ Export CSV"
        checksTable history
    div_ [class_ "split"] $ do
        div_ [class_ "panel"] $ do
            div_ [class_ "panel-head"] $ h2_ "Response contract"
            div_ [class_ "panel-body"] $ pre_ (toHtml (valueToText (endpointContract endpoint)))
        div_ [class_ "panel"] $ do
            div_ [class_ "panel-head"] $ h2_ "Monitor controls"
            div_ [class_ "panel-body"] $ do
                p_ [class_ "muted"] "Pausing preserves your configuration and history. Deleting permanently removes both."
                div_ [class_ "actions"] $ do
                    form_ [method_ "post",action_ (path <> "/toggle")] $ button_ [type_ "submit",class_ "btn btn-secondary"] (if endpointEnabled endpoint then "Pause monitor" else "Resume monitor")
                    form_ [method_ "post",action_ (path <> "/delete"),attr "data-confirm" "Permanently delete this monitor and all its check history?"] $ button_ [type_ "submit",class_ "btn btn-danger"] "Delete monitor"
  where
    path = endpointPath endpoint
    tick :: CheckResult -> Html ()
    tick check = span_ [class_ ("uptime-tick" <> if checkPassed check then "" else " fail"),title_ (text (checkTime check) <> " · " <> if checkPassed check then "Passing" else "Failing")] ""

checksTable :: [CheckResult] -> Html ()
checksTable [] = div_ [class_ "empty"] "No checks recorded in this period."
checksTable checks = div_ [class_ "table-container"] $ table_ $ do
    thead_ $ tr_ $ mapM_ th_ ["Time","Result","HTTP","Latency","Validation details"]
    tbody_ $ mapM_ row checks
  where
    row :: CheckResult -> Html ()
    row c = tr_ $ do
        td_ (timestamp (checkTime c))
        td_ $ span_ [class_ ("status-badge " <> if checkPassed c then "status-ok" else "status-fail")] (if checkPassed c then "Passed" else "Failed")
        td_ (toHtml (if checkStatus c == 0 then "Network" else text (checkStatus c)))
        td_ (toHtml (text (checkLatencyMs c) <> " ms"))
        td_ $ if checkPassed c then span_ [class_ "muted"] "Contract matched" else details_ $ do summary_ "View errors"; pre_ [class_ "error-detail"] (toHtml (valueToText (checkErrors c)))

latencyChart :: [CheckResult] -> Html ()
latencyChart [] = div_ [class_ "chart-zero"] "Your response-time chart will appear after the first check."
latencyChart recent = toHtmlRaw markup
  where
    checks = reverse (take 60 recent)
    maximumMs = max 1 (maximum (map checkLatencyMs checks))
    point (i,c) = text (40 + (i * 640 `div` max 1 (length checks-1))) <> "," <> text (145 - checkLatencyMs c * 120 `div` maximumMs)
    points = T.intercalate " " (map point (zip [0..] checks))
    markup = "<svg class=\"chart\" viewBox=\"0 0 720 180\" role=\"img\" aria-label=\"Recent response times in milliseconds\"><title>Response time for recent checks</title>"
        <> "<path class=\"chart-grid\" d=\"M40 25H695 M40 85H695 M40 145H695\"/>"
        <> "<text class=\"chart-label\" x=\"0\" y=\"29\">" <> text maximumMs <> "</text><text class=\"chart-label\" x=\"0\" y=\"149\">0 ms</text>"
        <> "<polygon class=\"chart-area\" points=\"40,145 " <> points <> " 680,145\"/><polyline class=\"chart-line\" points=\"" <> points <> "\"/>"
        <> "<text class=\"chart-label\" x=\"40\" y=\"173\">Earlier</text><text class=\"chart-label\" x=\"655\" y=\"173\">Latest</text></svg>"

incidentsHtml :: [(T.Text,T.Text,Int,Int,UTCTime,Value)] -> Html ()
incidentsHtml incidents = layout "incidents" "Incidents" $ do
    pageHeader "WHEN THINGS CHANGE" "A clear view of every failure." "Recent failed checks, including HTTP errors and contract mismatches." (a_ [href_ "/endpoints",class_ "btn btn-secondary"] "View monitors")
    div_ [class_ "panel"] $ do
        div_ [class_ "panel-head"] $ do h2_ "Failed checks"; span_ [class_ "muted"] "Latest 50"
        if null incidents then div_ [class_ "empty"] $ do strong_ "No failed checks recorded."; p_ "Failures will appear here with their HTTP status and validation details."
        else div_ [class_ "table-container"] $ table_ $ do
            thead_ $ tr_ $ mapM_ th_ ["Endpoint","HTTP","Latency","Time","Details"]
            tbody_ $ mapM_ row incidents
  where
    row :: (T.Text,T.Text,Int,Int,UTCTime,Value) -> Html ()
    row (name,url,status,latency,time,errors) = tr_ $ do
        td_ $ do strong_ (toHtml name); span_ [class_ "endpoint-url mono",title_ url] (toHtml url)
        td_ $ span_ [class_ "status-badge status-fail"] (toHtml (if status == 0 then "Network" else text status))
        td_ (toHtml (text latency <> " ms"))
        td_ (timestamp time)
        td_ $ details_ $ do summary_ "View errors"; pre_ [class_ "error-detail"] (toHtml (valueToText errors))
incidentPreview :: (T.Text,T.Text,Int,Int,UTCTime,Value) -> Html ()
incidentPreview (name,_,status,_,time,_) = div_ [class_ "incident-entry"] $ do
    strong_ (toHtml name)
    div_ [class_ "incident-meta"] $ do span_ (toHtml (if status == 0 then "Connection or validation failure" else "HTTP " <> text status)); timestamp time

timestamp :: UTCTime -> Html ()
timestamp time = time_ [datetime_ (T.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" time))] (toHtml (T.pack (formatTime defaultTimeLocale "%d %b %H:%M UTC" time)))
valueToText :: Value -> T.Text
valueToText = TL.toStrict . TLE.decodeUtf8 . encode

playgroundHtml :: Html ()
playgroundHtml = layout "playground" "Contract playground" $ do
    pageHeader "EXPERIMENT WITHOUT THE GUESSWORK" "Meet your next contract." "Validate sample JSON, explore examples, and catch drift before adding a monitor." mempty
    div_ [class_ "callout"] "This playground validates the JSON you provide. It makes no outbound requests and stores neither input."
    form_ [id_ "playground"] $ do
        div_ [class_ "actions"] $ do
            span_ [class_ "muted"] "Load an example:"
            preset "health" "Health endpoint"
            preset "users" "User collection"
            preset "drift" "Breaking change"
        div_ [class_ "playground-grid"] $ do
            div_ [class_ "form-row"] $ do label_ [for_ "contract"] "Contract"; textarea_ [id_ "contract",required_ "required",maxlength_ "32768",spellcheck_ "false"] (toHtml defaultContract)
            div_ [class_ "form-row"] $ do label_ [for_ "response"] "Sample response"; textarea_ [id_ "response",required_ "required",maxlength_ "65536",spellcheck_ "false"] "{\n  \"status\": \"ok\"\n}"
        div_ [class_ "actions"] $ do
            button_ [id_ "validate-contract",type_ "submit",class_ "btn"] "Run validation →"
            button_ [type_ "button",class_ "btn btn-secondary",attr "data-format" "contract"] "Format contract"
            button_ [type_ "button",class_ "btn btn-secondary",attr "data-format" "response"] "Format response"
    div_ [class_ "panel"] $ do
        div_ [class_ "panel-head"] $ h2_ "Validation result"
        div_ [class_ "panel-body"] $ pre_ [id_ "playground-result",class_ "result-box",attr "role" "status",attr "aria-live" "polite"] "Ready when you are. Run validation to compare the response with your contract."
  where
    preset :: T.Text -> T.Text -> Html ()
    preset key label = button_ [type_ "button",class_ "btn btn-secondary btn-sm",attr "data-preset" key] (toHtml (label :: T.Text))

errorHtml :: T.Text -> T.Text -> Html ()
errorHtml title message = layout "monitors" title $ do
    pageHeader "REQUEST COULD NOT BE COMPLETED" title "Your existing monitor data has been preserved." mempty
    div_ [class_ "error-box",attr "role" "alert"] (toHtml message)
    div_ [class_ "actions"] $ do a_ [href_ "/endpoints",class_ "btn"] "Back to monitors"; a_ [href_ "/endpoints/new",class_ "btn btn-secondary"] "Add a monitor"

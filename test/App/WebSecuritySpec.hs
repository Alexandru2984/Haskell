{-# LANGUAGE OverloadedStrings #-}
module App.WebSecuritySpec (spec) where
import Test.Hspec
import Network.Wai (defaultRequest, requestHeaders)
import App.Security.Web (trustedWrite)

spec :: Spec
spec = describe "write origin protection" $ do
    let trusted = trustedWrite "https://haskell.micutu.com"
    it "rejects absent origins, opaque origins and sibling subdomains" $ do
        trusted defaultRequest `shouldBe` False
        trusted defaultRequest {requestHeaders=[("Origin","null")]} `shouldBe` False
        trusted defaultRequest {requestHeaders=[("Origin","https://evil.micutu.com")]} `shouldBe` False
    it "rejects origin-prefix and userinfo spoofing" $ do
        trusted defaultRequest {requestHeaders=[("Origin","https://haskell.micutu.com.evil.test")]} `shouldBe` False
        trusted defaultRequest {requestHeaders=[("Referer","https://haskell.micutu.com@evil.test/")]} `shouldBe` False
    it "accepts the configured origin and exact-origin referers" $ do
        trusted defaultRequest {requestHeaders=[("Origin","https://haskell.micutu.com")]} `shouldBe` True
        trusted defaultRequest {requestHeaders=[("Referer","https://haskell.micutu.com/endpoints/new")]} `shouldBe` True
    it "rejects cross-site fetch metadata even with a matching origin" $
        trusted defaultRequest {requestHeaders=[("Origin","https://haskell.micutu.com"),("Sec-Fetch-Site","cross-site")]} `shouldBe` False

module Main (main) where
import Test.Hspec (hspec)
import qualified App.CheckerSpec as Checker
import qualified App.ConfigSpec as Config
import qualified App.ContractSpec as Contract
import qualified App.UrlSafetySpec as UrlSafety
import qualified App.ValidatorSpec as Validator
import qualified App.WebSecuritySpec as WebSecurity

main :: IO ()
main = hspec $ do
    Checker.spec
    Config.spec
    Contract.spec
    UrlSafety.spec
    Validator.spec
    WebSecurity.spec

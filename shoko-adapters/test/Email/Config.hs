module Email.Config (tests) where

import Data.IORef
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Email.Contract hiding (key, tests)
import EmailSmoke.Config qualified as C
import Settei qualified as S
import Settei.Env qualified as Env
import Settei.Yaml qualified as Y
import Shoko.Adapter.Email qualified as E
import Test.Tasty

yaml :: Text -> IO S.Source
yaml text = either (const (fail "test YAML invalid")) pure (Y.decodeYamlSource (Y.yamlSourceOptions "explicit email YAML") (T.encodeUtf8 text))

key :: Text -> S.Key
key = either (error . show) id . S.parseKey

config :: IO C.Config
config = fst <$> right (C.resolveSources [])

tests :: TestTree
tests =
  testGroup
    "Settei email host boundary"
    [ test "defaults, explicit YAML, then explicit environment win with provenance" $ do
        defaults <- config
        check (E.pageSize (C.limits defaults) == 100)
        file <- yaml "bounds:\n  pageSize: 20\n"
        bindings <- either (const (fail "test bindings invalid")) pure (Env.bindings [Env.binding (Env.EnvName "EMAIL_PAGE") (key "bounds.pageSize")])
        let environment = Env.environmentSource bindings (Env.envSnapshot [("EMAIL_PAGE", "30")])
        (resolved, report) <- right (C.resolveSources [file, environment])
        check (E.pageSize (C.limits resolved) == 30)
        check ("EMAIL_PAGE" `T.isInfixOf` report && "explicit email YAML" `T.isInfixOf` report),
      test "unknown keys, invalid winning values and cross-field budgets fail closed" $ do
        file <- yaml "bounds:\n  pageSize: 20\n"
        mapM_
          ( \text -> do
              override <- yaml text
              check (either (const True) (const False) (C.resolveSources [file, override]))
          )
          [ "bounds:\n  pageSize: 0\n",
            "bounds:\n  pageSize: 101\n",
            "bounds:\n  requestMs: 29000\n",
            "policy:\n  executionMs: 1000\n",
            "unknown: true\n",
            "provider: other\n",
            "access:\n  apiKeyEnv: 'not an env'\n",
            "access:\n  apiKeyEnv: SHOKO_EMAIL_RECEIVING_DOMAIN\n",
            "bounds:\n  responseBytes: 4000000\n"
          ],
      test "missing, empty and invalid secret winners never fall back or leak" $ do
        selected <- config
        missing <- C.resolvePrivateWith (const (pure Nothing)) True selected
        check (either (== "email-private-inputs-unavailable") (const False) missing)
        let values name = pure $ lookup name [("SHOKO_EMAIL_RESEND_API_KEY", ""), ("SHOKO_EMAIL_RECEIVING_DOMAIN", "fixture.invalid"), ("SHOKO_EMAIL_SENDER", "approved@sender.invalid")]
        empty <- C.resolvePrivateWith values True selected
        check (either (== "email-private-inputs-unavailable") (const False) empty)
        let invalid name = pure $ lookup name [("SHOKO_EMAIL_RESEND_API_KEY", "CREDENTIAL-PRIVATE"), ("SHOKO_EMAIL_RECEIVING_DOMAIN", "https://URL-PRIVATE.invalid"), ("SHOKO_EMAIL_SENDER", "FROM-PRIVATE")]
        rejected <- C.resolvePrivateWith invalid True selected
        check (either (== "email-private-inputs-unavailable") (const False) rejected),
      test "receiving-only resolution never reads or requires a sender" $ do
        selected <- config
        looked <- newIORef []
        let values name = do
              modifyIORef' looked (name :)
              pure $ lookup name [("SHOKO_EMAIL_RESEND_API_KEY", "CREDENTIAL-PRIVATE"), ("SHOKO_EMAIL_RECEIVING_DOMAIN", "fixture.invalid")]
        receive <- C.resolvePrivateWith values False selected
        check (either (const False) (const True) receive)
        readIORef looked >>= check . notElem "SHOKO_EMAIL_SENDER"
        send <- C.resolvePrivateWith values True selected
        check (either (== "email-private-inputs-unavailable") (const False) send),
      test "configuration stores references and keeps private values out of reports" $ do
        file <- yaml "access:\n  apiKeyEnv: TEST_KEY\n  domainEnv: TEST_DOMAIN\n  senderEnv: TEST_SENDER\n"
        (selected, report) <- right (C.resolveSources [file])
        calls <- newIORef (0 :: Int)
        let values name = modifyIORef' calls (+ 1) >> pure (lookup name [("TEST_KEY", "CREDENTIAL-PRIVATE"), ("TEST_DOMAIN", "fixture.invalid"), ("TEST_SENDER", "FROM-PRIVATE@sender.invalid")])
        resolved <- C.resolvePrivateWith values True selected
        check (either (const False) (const True) resolved)
        readIORef calls >>= check . (== 3)
        mapM_ (\sentinel -> check (not (sentinel `T.isInfixOf` report))) ["CREDENTIAL-PRIVATE", "fixture.invalid", "FROM-PRIVATE"]
    ]

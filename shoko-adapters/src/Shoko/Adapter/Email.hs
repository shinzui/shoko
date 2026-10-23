module Shoko.Adapter.Email
  ( Inbox,
    inbox,
    EmailLimits (..),
    EmailReader,
    Address,
    address,
    addressText,
    recipient,
    freshToken,
    ReceivedEmail,
    emailTo,
    emailFrom,
    emailSubject,
    emailText,
    emailHtml,
    emailHtmlFormat,
    emailHeaders,
    emailAttachments,
    Attachment,
    attachmentName,
    attachmentType,
    attachmentSize,
    attachmentId,
    SendDescriptor,
    sendDescriptor,
    EmailPayload,
    emailPayload,
    EmailSubmission,
    emailObservationHandler,
    emailActionHandler,
  )
where

import Control.Concurrent.MVar (modifyMVar)
import Control.Monad (foldM)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Shoko.Action
import Shoko.Adapter.Email.Internal
import Shoko.Binding
import Shoko.Clock
import Shoko.Environment
import Shoko.Observation

-- Descriptions are pure. Capture checks descriptor ownership before listing anything.
emailObservationHandler :: Inbox -> Input Text -> (ReceivedEmail -> Either Text a) -> Either HandlerBuildError (Handler EmailReader a)
emailObservationHandler descriptor@(Inbox label _ semantic _ _ limits) token decode =
  Right $ observationHandler (requiring [SendHttp, ReadState] noRequirements) (RequiresBusinessKey semantic) source $ \(EmailReader actual _ provider state) context ->
    if descriptor /= actual
      then pure (ObservationUnavailable "email-descriptor-mismatch")
      else guardCorrelation semantic token context $ do
        selected <- resolveInput context token
        case either (const (Left "email-input-unavailable")) (recipient descriptor) selected of
          Left _ -> pure (ObservationUnavailable "email-correlation-unavailable")
          Right destination -> do
            start <- monotonic (callClock context)
            let clock = callClock context
                end = min (requestDeadline context) (addDuration start (scanLimit limits))
            result <- bounded clock end $ modifyMVar state $ \original@(ReaderState baselines ids) ->
              case sourceBaseline context >>= (\b -> if sourceOf b == label then cursorOf b >>= (`Map.lookup` baselines) else Nothing) of
                Nothing -> pure (original, Left "email-baseline-unavailable")
                Just old ->
                  scan provider actual clock end >>= \case
                    Left failure -> pure (original, Left failure)
                    Right (refs, pages, bytes) -> do
                      let candidates = [(identity, recipients) | (identity, recipients) <- Map.toList refs, Set.notMember identity old, destination `elem` recipients]
                      if length candidates > maxDetails limits
                        then pure (original, Left "email-detail-limit")
                        else do
                          fetched <- foldM (fetch provider clock end destination) (Right ([], bytes)) candidates
                          case fetched of
                            Left failure -> pure (original, Left failure)
                            Right (values, _) -> do
                              updated <- foldM (\m (identity, _) -> if Map.member identity m then pure m else (\fresh -> Map.insert identity fresh m) <$> freshToken) ids values
                              pure (ReaderState baselines updated, Right ([Occurrence (Map.lookup identity updated) value | (identity, value) <- values], pages))
            finish <- monotonic clock
            pure $ case result of
              Just (Right (values, pages)) | finish <= end -> ObservedWithDetails values (Coverage SampledState start finish True) [("provider", PublicChoice "resend"), ("pages", PublicCount (toInteger pages)), ("operation", PublicChoice "receive")]
              Just (Left failure) -> ObservationUnavailable failure
              _ -> ObservationUnavailable "email-deadline"
  where
    source = newSource label SampledState $ \(EmailReader actual _ provider state) clock ->
      if actual /= descriptor
        then pure (Left "email-descriptor-mismatch")
        else do
          start <- monotonic clock
          let end = addDuration start (scanLimit limits)
          result <- bounded clock end $ modifyMVar state $ \original@(ReaderState baselines ids) ->
            scan provider descriptor clock end >>= \case
              Left failure -> pure (original, Left failure)
              Right (refs, _, _) -> do
                handle <- freshToken
                captured <- monotonic clock
                pure (ReaderState (Map.insert handle (Map.keysSet refs) baselines) ids, Right (Baseline label captured (Just handle)))
          pure $ maybe (Left "email-baseline-deadline") id result
    fetch provider clock end destination accumulated (identity, listedRecipients) = case accumulated of
      Left failure -> pure (Left failure)
      Right (values, bytes) ->
        getDetail provider clock end identity >>= \case
          Left failure -> pure (Left failure)
          Right (email, size)
            | receivedId email /= identity || emailTo email /= listedRecipients || destination `notElem` emailTo email -> pure (Left "email-identity-disagreement")
            | bytes + size > scanBytes limits -> pure (Left "email-scan-limit")
            | otherwise -> pure $ case decode email of
                Left _ -> Left "email-content-undecodable"
                Right value -> Right ((identity, value) : values, bytes + size)
    sourceOf Baseline {source = value} = value
    cursorOf Baseline {cursor = value} = value

-- A send is one external mutation attempt. Its response establishes acceptance only.
emailActionHandler :: SendDescriptor -> (CallContext -> IO (Either Text EmailPayload)) -> Either HandlerBuildError (Handler EmailReader EmailSubmission)
emailActionHandler descriptor@(SendDescriptor inboxDescriptor _) build = Right $
  actionHandler (requiring [SendHttp, WriteState, ExternalSideEffect] noRequirements) $ \(EmailReader actual sending provider _) context ->
    if actual /= inboxDescriptor || sending /= Just descriptor
      then pure (ActionUnavailable "email-descriptor-mismatch")
      else
        build context >>= \case
          Left _ -> pure (ActionUnavailable "email-payload-unavailable")
          Right payload | not (payloadAllowed descriptor payload) -> pure (ActionUnavailable "email-destination-denied")
          Right payload ->
            submit provider (callClock context) (requestDeadline context) payload >>= \case
              Left failure -> pure (ActionUnavailable failure)
              Right accepted -> pure (ActionObservedWithDetails "accepted" accepted [("provider", PublicChoice "resend"), ("operation", PublicChoice "send")])

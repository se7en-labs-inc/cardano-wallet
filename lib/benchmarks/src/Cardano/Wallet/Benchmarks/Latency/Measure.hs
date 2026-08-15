{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

module Cardano.Wallet.Benchmarks.Latency.Measure
    ( -- * Measuring traces
      withLatencyLogging
    , measureApiLogs
    , LogCaptureFunc

      -- * Formatting results
    , fmtResult
    , fmtTitle
    , meanAvg
    ) where

import Control.Monad
    ( replicateM_
    )
import Control.Monad.Cont
    ( ContT (..)
    )
import Control.Monad.IO.Class
    ( MonadIO (..)
    )
import Data.Maybe
    ( mapMaybe
    )
import Data.Time
    ( NominalDiffTime
    , UTCTime
    )
import Data.Time.Clock
    ( diffUTCTime
    )
import Fmt
    ( Builder
    , build
    , fixedF
    , fmt
    , fmtLn
    , indentF
    , padLeftF
    , (+|)
    , (|+)
    )
import Network.Wai.Middleware.Logging
    ( ApiLog (..)
    , HandlerLog (..)
    )
import UnliftIO.STM
    ( TVar
    , atomically
    , modifyTVar
    , newTVarIO
    , readTVarIO
    , writeTVar
    )
import Prelude

meanAvg :: [NominalDiffTime] -> Double
meanAvg ts = sum (map realToFrac ts) * 1000 / fromIntegral (length ts)

buildResult :: [NominalDiffTime] -> Builder
buildResult [] = "ERR"
buildResult ts = build $ fixedF 1 $ meanAvg ts

fmtTitle :: Builder -> IO ()
fmtTitle title = fmt (indentF 4 title)

fmtResult :: String -> [NominalDiffTime] -> IO ()
fmtResult title ts =
    let titleExt = title |+ " - " :: String
        titleF = padLeftF 30 ' ' titleExt
    in  fmtLn (titleF +| buildResult ts |+ " ms")

isLogRequestStart :: ApiLog -> Bool
isLogRequestStart = \case
    ApiLog _ LogRequestStart -> True
    _ -> False

isLogRequestFinish :: ApiLog -> Bool
isLogRequestFinish = \case
    ApiLog _ LogRequestFinish -> True
    _ -> False

measureApiLogs
    :: Int -> LogCaptureFunc ApiLog () -> IO a -> IO [NominalDiffTime]
measureApiLogs count = measureLatency count isLogRequestStart isLogRequestFinish

-- | Measure how long an action takes based on trace points and taking an
-- average of results over a short time period.
measureLatency
    :: Show msg
    => Int
    -> (msg -> Bool)
    -- ^ Predicate for start message
    -> (msg -> Bool)
    -- ^ Predicate for end message
    -> LogCaptureFunc msg ()
    -- ^ Log capture function.
    -> IO a
    -- ^ Action to run
    -> IO [NominalDiffTime]
measureLatency count start finish capture action = do
    (logs, ()) <- capture $ replicateM_ count action
    pure $ extractTimings start finish logs

-- | Scan through captured logs and extract time differences between
-- start and end messages.
extractTimings
    :: forall a
     . Show a
    => (a -> Bool)
    -- ^ Predicate for start message
    -> (a -> Bool)
    -- ^ Predicate for end message
    -> [(UTCTime, a)]
    -- ^ Timestamped log messages
    -> [NominalDiffTime]
extractTimings isStart isFinish msgs =
    map2 mkDiff
        $ if even (length filtered)
            then filtered
            else error "start trace without matching finish trace"
  where
    map2
        :: ((Bool, UTCTime) -> (Bool, UTCTime) -> NominalDiffTime)
        -> [(Bool, UTCTime)]
        -> [NominalDiffTime]
    map2 _ [] = []
    map2 f (a : b : xs) = f a b : map2 f xs
    map2 _ _ = error "start trace without matching finish trace"

    mkDiff :: (Bool, UTCTime) -> (Bool, UTCTime) -> NominalDiffTime
    mkDiff (False, start) (True, finish) = diffUTCTime finish start
    mkDiff (False, _) _ = error "Missing finish trace"
    mkDiff (True, _) _ = error "Missing start trace"

    filtered :: [(Bool, UTCTime)]
    filtered = mapMaybe filterMsg msgs

    filterMsg :: (UTCTime, a) -> Maybe (Bool, UTCTime)
    filterMsg (t, msg)
        | isStart msg = Just (False, t)
        | isFinish msg = Just (True, t)
        | otherwise = Nothing

type LogCaptureFunc msg b = IO b -> IO ([(UTCTime, msg)], b)

withLatencyLogging
    :: (TVar [(UTCTime, ApiLog)] -> tracers)
    -> ContT r IO (tracers, LogCaptureFunc ApiLog b)
withLatencyLogging setupTracers = do
    tvar <- liftIO $ newTVarIO []
    pure (setupTracers tvar, logCaptureFunc tvar)

logCaptureFunc :: TVar [(UTCTime, a)] -> LogCaptureFunc a b
logCaptureFunc tvar action = do
    atomically $ writeTVar tvar []
    res <- action
    logs <- readTVarIO tvar
    pure (reverse logs, res)

{-# LANGUAGE NumericUnderscores #-}

module Cardano.Wallet.Network.ImplementationSpec
    ( spec
    ) where

import Cardano.Wallet.Network.Implementation
    ( handleIOException
    , recoveringNodeConnection
    , retryOnConnectionLost
    , runBoundedQuery
    )
import Control.Concurrent
    ( newEmptyMVar
    , putMVar
    , takeMVar
    , threadDelay
    )
import Control.Exception
    ( finally
    , throwIO
    )
import Control.Monad
    ( forever
    , when
    )
import Control.Retry
    ( RetryAction (..)
    )
import Control.Tracer
    ( nullTracer
    )
import Data.IORef
    ( atomicModifyIORef'
    , newIORef
    , readIORef
    )
import Foreign.C.Error
    ( Errno
    , eACCES
    , eINVAL
    , errnoToIOError
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )
import Prelude

import qualified Network.Mux as Mux

spec :: Spec
spec = do
    describe "handleIOException" $ do
        it "retries a failed read on a Windows named pipe"
            $ classify (pipeError "withIODataPtr (readHandle)" eINVAL)
                >>= (`shouldBe` ConsultPolicy)

        it "retries a failed write on a Windows named pipe"
            $ classify (pipeError "withIODataPtr (writeHandle)" eINVAL)
                >>= (`shouldBe` ConsultPolicy)

        it "does not retry an invalid argument raised elsewhere"
            $ classify (pipeError "recv" eINVAL)
                >>= (`shouldBe` DontRetry)

        it "does not retry a permission error at the pipe location"
            $ classify (pipeError "withIODataPtr (readHandle)" eACCES)
                >>= (`shouldBe` DontRetry)

    describe "recoveringNodeConnection" $ do
        it "retries a mux error from an aborted pipe read"
            $ do
                calls <- newIORef (0 :: Int)
                let action = do
                        n <- atomicModifyIORef' calls
                            $ \c -> (c + 1, c)
                        when (n == 0) $ throwIO abortedRead
                recoveringNodeConnection
                    nullTracer
                    (retryOnConnectionLost nullTracer)
                    action
                readIORef calls >>= (`shouldBe` 2)

    describe "runBoundedQuery" $ do
        it "cancels an isolated client and query on timeout" $ do
            clientStarted <- newEmptyMVar
            clientStopped <- newEmptyMVar
            queryStarted <- newEmptyMVar
            queryStopped <- newEmptyMVar
            let stalled started stopped =
                    (putMVar started () >> forever (threadDelay 1_000_000))
                        `finally` putMVar stopped ()

            result <-
                runBoundedQuery
                    (takeMVar clientStarted >> takeMVar queryStarted)
                    (stalled clientStarted clientStopped)
                    (stalled queryStarted queryStopped :: IO Int)

            result `shouldBe` Nothing
            takeMVar clientStopped
            takeMVar queryStopped

        it "returns the result and cancels its isolated client" $ do
            clientStarted <- newEmptyMVar
            clientStopped <- newEmptyMVar
            let client =
                    (putMVar clientStarted () >> forever (threadDelay 1_000_000))
                        `finally` putMVar clientStopped ()

            result <-
                runBoundedQuery
                    (threadDelay 1_000_000)
                    client
                    (takeMVar clientStarted >> pure (42 :: Int))

            result `shouldBe` Just 42
            takeMVar clientStopped
  where
    classify = handleIOException nullTracer
    abortedRead =
        Mux.IOException
            (pipeError "withIODataPtr (readHandle)" eINVAL)
            "readHandle errored"

-- | Build an error the way the Win32 package does.
pipeError :: String -> Errno -> IOError
pipeError loc errno = errnoToIOError loc errno Nothing Nothing

{-# LANGUAGE DefaultSignatures #-}

module Cardano.BM.Data.Tracer
    ( HasPrivacyAnnotation (..)
    , HasSeverityAnnotation (..)
    , filterSeverity
      -- * Re-exports for convenience
    , Tracer
    , traceWith
    , nullTracer
    , contramap
    ) where

import Cardano.BM.Data.LogItem
    ( PrivacyAnnotation (..)
    )
import Cardano.BM.Data.Severity
    ( Severity (..)
    )
import Control.Monad
    ( when
    )
import Control.Tracer
    ( Tracer
    , contramap
    , mkTracer
    , nullTracer
    , traceWith
    )
import Data.Text
    ( Text
    )
import Prelude

class HasPrivacyAnnotation a where
    getPrivacyAnnotation :: a -> PrivacyAnnotation
    default getPrivacyAnnotation :: a -> PrivacyAnnotation
    getPrivacyAnnotation _ = Public

class HasSeverityAnnotation a where
    getSeverityAnnotation :: a -> Severity

instance HasPrivacyAnnotation Text

instance HasSeverityAnnotation Text where
    getSeverityAnnotation _ = Debug

-- | Filter a tracer, keeping only messages at or above a dynamic severity
-- threshold. The threshold function receives the message and returns a severity;
-- messages with getSeverityAnnotation >= that threshold are forwarded.
filterSeverity
    :: (Monad m, HasSeverityAnnotation a)
    => (a -> m Severity)
    -> Tracer m a
    -> Tracer m a
filterSeverity msevlimit tr = mkTracer $ \arg -> do
    sevlimit <- msevlimit arg
    when (getSeverityAnnotation arg >= sevlimit) $
        traceWith tr arg

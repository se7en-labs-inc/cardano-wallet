module Cardano.BM.Tracing
    ( -- * Severity
      Severity (..)
      -- * Privacy
    , PrivacyAnnotation (..)
    , HasPrivacyAnnotation (..)
    , HasSeverityAnnotation (..)
      -- * Tracers (re-exports from contra-tracer)
    , Tracer
    , traceWith
    , contramap
    , nullTracer
      -- * Simplified Trace type
    , Trace
    , appendName
      -- * Structured logging marker (no-op)
    , ToObject (..)
    ) where

import Cardano.BM.Data.LogItem
    ( PrivacyAnnotation (..)
    )
import Cardano.BM.Data.Severity
    ( Severity (..)
    )
import Cardano.BM.Data.Tracer
    ( HasPrivacyAnnotation (..)
    , HasSeverityAnnotation (..)
    )
import Control.Tracer
    ( Tracer
    , contramap
    , nullTracer
    , traceWith
    )
import Data.Text
    ( Text
    )
import Prelude

-- | In the simplified model, a Trace is just a Tracer.
type Trace m a = Tracer m a

-- | Append a name component to a trace hierarchy. In this simplified
-- implementation the name is ignored and the tracer is returned unchanged.
appendName :: Text -> Trace m a -> Trace m a
appendName _ = id

-- | Marker typeclass for types that can be serialised as structured log
-- objects. No methods required in the simplified implementation.
class ToObject a

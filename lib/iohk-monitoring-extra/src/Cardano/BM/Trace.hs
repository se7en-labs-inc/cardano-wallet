module Cardano.BM.Trace
    ( Trace
    , appendName
    , nullTracer
    , traceInTVar
    , traceInTVarIO
    ) where

import Cardano.BM.Tracing
    ( Trace
    , appendName
    )
import Control.Concurrent.STM
    ( STM
    , TVar
    , atomically
    , modifyTVar
    )
import Control.Tracer
    ( mkTracer
    , nullTracer
    )
import Prelude

-- | Capture all traced messages in an STM TVar (STM variant).
traceInTVar :: TVar [a] -> Trace STM a
traceInTVar tvar = mkTracer $ \a -> modifyTVar tvar (a :)

-- | Capture all traced messages in an IO TVar.
traceInTVarIO :: TVar [a] -> Trace IO a
traceInTVarIO tvar = mkTracer $ \a -> atomically $ modifyTVar tvar (a :)

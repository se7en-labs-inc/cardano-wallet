{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Cardano.BM.Data.Severity
    ( Severity (..)
    ) where

import Data.Aeson
    ( FromJSON
    , ToJSON
    )
import GHC.Generics
    ( Generic
    )
import Prelude

data Severity
    = Debug
    | Info
    | Notice
    | Warning
    | Error
    | Critical
    | Alert
    | Emergency
    deriving (Eq, Ord, Show, Read, Enum, Bounded, Generic, ToJSON, FromJSON)

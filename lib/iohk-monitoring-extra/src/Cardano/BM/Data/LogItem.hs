{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}

module Cardano.BM.Data.LogItem
    ( PrivacyAnnotation (..)
    , LoggerName
    ) where

import Data.Aeson
    ( ToJSON
    )
import Data.Text
    ( Text
    )
import GHC.Generics
    ( Generic
    )
import Prelude

type LoggerName = Text

data PrivacyAnnotation
    = Public
    | Confidential
    deriving (Eq, Ord, Show, Generic, ToJSON)

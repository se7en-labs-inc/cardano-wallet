{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Cardano.BM.Data.Output
    ( ScribeKind (..)
    , ScribeFormat (..)
    , ScribePrivacy (..)
    , ScribeDefinition (..)
    , RotationParameters
    ) where

import Cardano.BM.Data.Severity
    ( Severity
    )
import Data.Aeson
    ( FromJSON
    , ToJSON
    )
import Data.Text
    ( Text
    )
import GHC.Generics
    ( Generic
    )
import Prelude

data ScribeKind
    = FileSK
    | StdoutSK
    | StderrSK
    | JournalSK
    | DevNullSK
    | UserDefinedSK
    deriving (Generic, Eq, Ord, Show, Read, FromJSON, ToJSON)

data ScribeFormat
    = ScText
    | ScJson
    deriving (Generic, Eq, Ord, Show, Read, FromJSON, ToJSON)

data ScribePrivacy
    = ScPublic
    | ScPrivate
    deriving (Generic, Eq, Ord, Show, FromJSON, ToJSON)

data RotationParameters = RotationParameters
    deriving (Generic, Eq, Ord, Show, FromJSON, ToJSON)

data ScribeDefinition = ScribeDefinition
    { scKind :: ScribeKind
    , scFormat :: ScribeFormat
    , scName :: Text
    , scPrivacy :: ScribePrivacy
    , scRotation :: Maybe RotationParameters
    , scMinSev :: Severity
    , scMaxSev :: Severity
    }
    deriving (Generic, Eq, Ord, Show, ToJSON)

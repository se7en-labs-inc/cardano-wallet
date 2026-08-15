{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TypeApplications #-}

-- |
-- Copyright: © 2024 Cardano Foundation
-- License: Apache-2.0
--
-- Tools for creating transactions that change the delegation status.
module Cardano.Wallet.Transaction.Delegation
    ( certificateFromDelegationAction
    ) where

import Cardano.Address.Derivation
    ( XPub
    , xpubPublicKey
    )
import Cardano.Address.KeyHash
    ( KeyHash (..)
    )
import Cardano.Address.Script
    ( Script (..)
    )
import Cardano.Balance.Tx.Eras
    ( RecentEra (..)
    )
import Cardano.Crypto.Hash.Class
    ( Hash (UnsafeHash)
    )
import Cardano.Wallet.Primitive.Ledger.Convert
    ( toLedgerDelegatee
    )
import Cardano.Wallet.Primitive.Ledger.Shelley
    ( toCardanoLovelace
    , toCardanoSimpleScript
    )
import Cardano.Wallet.Primitive.Types.Coin
    ( Coin
    )
import Cardano.Wallet.Transaction
    ( DelegationAction (..)
    )
import Cryptography.Hash.Blake
    ( blake2b224
    )
import Data.ByteString.Short
    ( toShort
    )
import Prelude

import qualified Cardano.Api as Cardano
import qualified Cardano.Api.Experimental.Certificate as ExpCert
import qualified Cardano.Api.Ledger as Ledger

{-----------------------------------------------------------------------------
    Cardano.Certificate
------------------------------------------------------------------------------}
certificateFromDelegationAction
    :: RecentEra era
    -- ^ Era in which we create the certificate
    -> Either XPub (Script KeyHash)
    -- ^ Our staking credential
    -> Maybe Coin
    -- ^ Optional deposit value
    -> DelegationAction
    -- ^ Delegation action that we plan to take
    -> [ExpCert.Certificate era]
    -- ^ Certificates representing the action
certificateFromDelegationAction RecentEraConway cred depositM da =
    case (da, depositM) of
        (Join poolId, _) ->
            [ ExpCert.makeStakeAddressDelegationCertificate @Cardano.ConwayEra
                (toCardanoStakeCredential cred)
                (toLedgerDelegatee (Just poolId) Nothing)
            ]
        (JoinRegisteringKey poolId, Just deposit) ->
            [ ExpCert.makeStakeAddressRegistrationCertificate @Cardano.ConwayEra
                (toCardanoStakeCredential cred)
                (toCardanoLovelace deposit)
            , ExpCert.makeStakeAddressDelegationCertificate @Cardano.ConwayEra
                (toCardanoStakeCredential cred)
                (toLedgerDelegatee (Just poolId) Nothing)
            ]
        (JoinRegisteringKey _, Nothing) ->
            error
                "certificateFromDelegationAction: deposit value required in \
                \Conway era when registration is carried out (joining)"
        (Quit, Just deposit) ->
            [ ExpCert.makeStakeAddressUnregistrationCertificate @Cardano.ConwayEra
                (toCardanoStakeCredential cred)
                (toCardanoLovelace deposit)
            ]
        (Quit, Nothing) ->
            error
                "certificateFromDelegationAction: deposit value required in \
                \Conway era when registration is carried out (quitting)"
certificateFromDelegationAction RecentEraDijkstra cred depositM da =
    case (da, depositM) of
        (Join poolId, _) ->
            [ ExpCert.makeStakeAddressDelegationCertificate @Cardano.DijkstraEra
                (toCardanoStakeCredential cred)
                (toLedgerDelegatee (Just poolId) Nothing)
            ]
        (JoinRegisteringKey poolId, Just deposit) ->
            [ ExpCert.makeStakeAddressRegistrationCertificate @Cardano.DijkstraEra
                (toCardanoStakeCredential cred)
                (toCardanoLovelace deposit)
            , ExpCert.makeStakeAddressDelegationCertificate @Cardano.DijkstraEra
                (toCardanoStakeCredential cred)
                (toLedgerDelegatee (Just poolId) Nothing)
            ]
        (JoinRegisteringKey _, Nothing) ->
            error
                "certificateFromDelegationAction: deposit value required in \
                \Dijkstra era when registration is carried out (joining)"
        (Quit, Just deposit) ->
            [ ExpCert.makeStakeAddressUnregistrationCertificate @Cardano.DijkstraEra
                (toCardanoStakeCredential cred)
                (toCardanoLovelace deposit)
            ]
        (Quit, Nothing) ->
            error
                "certificateFromDelegationAction: deposit value required in \
                \Dijkstra era when registration is carried out (quitting)"

{-----------------------------------------------------------------------------
    Cardano.StakeCredential
------------------------------------------------------------------------------}

toCardanoStakeCredential
    :: Either XPub (Script KeyHash) -> Cardano.StakeCredential
toCardanoStakeCredential = \case
    Left xpub ->
        Cardano.StakeCredentialByKey
            . toHashStakeKey
            $ xpub
    Right script ->
        Cardano.StakeCredentialByScript
            . Cardano.hashScript
            . Cardano.SimpleScript
            $ toCardanoSimpleScript script

toHashStakeKey :: XPub -> Cardano.Hash Cardano.StakeKey
toHashStakeKey =
    Cardano.StakeKeyHash
        . Ledger.KeyHash
        . UnsafeHash
        . toShort
        . blake2b224
        . xpubPublicKey

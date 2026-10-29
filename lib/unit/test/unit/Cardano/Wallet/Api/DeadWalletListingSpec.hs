{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- |
-- Copyright: © 2026 Cardano Foundation
-- License: Apache-2.0
--
-- A wallet whose worker has exited is still listed, with the state
-- @not_responding@, and its database is opened once per request.
module Cardano.Wallet.Api.DeadWalletListingSpec
    ( spec
    ) where

import Cardano.Address.Derivation
    ( XPrv
    , toXPub
    )
import Cardano.Address.Script
    ( Cosigner (..)
    , Script (..)
    , ScriptTemplate (..)
    )
import Cardano.Mnemonic
    ( SomeMnemonic (..)
    )
import Cardano.Wallet.Address.Derivation
    ( Depth (..)
    )
import Cardano.Wallet.Address.Derivation.Byron
    ( ByronKey
    )
import Cardano.Wallet.Address.Derivation.SharedKey
    ( SharedKey (SharedKey)
    )
import Cardano.Wallet.Address.Derivation.Shelley
    ( ShelleyKey (..)
    , generateKeyFromSeed
    )
import Cardano.Wallet.Address.Discovery
    ( ChangeAddressMode (..)
    , IsOurs
    )
import Cardano.Wallet.Address.Discovery.Random
    ( RndState
    , mkRndState
    )
import Cardano.Wallet.Address.Discovery.Sequential
    ( SeqState
    , defaultAddressPoolGap
    , purposeCIP1852
    )
import Cardano.Wallet.Address.Discovery.Shared
    ( SharedState
    )
import Cardano.Wallet.Address.Keys.SequentialAny
    ( mkSeqStateFromRootXPrv
    )
import Cardano.Wallet.Address.Keys.Shared
    ( mkSharedStateFromAccountXPub
    )
import Cardano.Wallet.Api
    ( ApiLayer (..)
    )
import Cardano.Wallet.Api.Http.Shelley.Server
    ( getWallet
    , listWallets
    , mkLegacyWallet
    , mkSharedWallet
    , mkShelleyWallet
    )
import Cardano.Wallet.Api.Types
    ( ApiActiveSharedWallet
    , ApiByronWallet
    , ApiSharedWallet (..)
    , ApiT (..)
    , ApiWallet
    )
import Cardano.Wallet.DB
    ( DBFactory (..)
    , DBLayerParams (..)
    )
import Cardano.Wallet.DB.Layer
    ( DefaultFieldValues (..)
    , PersistAddressBook
    , newDBFactory
    )
import Cardano.Wallet.DummyTarget.Primitive.Types
    ( block0
    , dummyGenesisParameters
    , dummyNetworkLayer
    , dummyNetworkParameters
    , dummyTimeInterpreter
    )
import Cardano.Wallet.Flavor
    ( CredFromOf
    , KeyFlavorS (..)
    , KeyOf
    , WalletFlavorS (..)
    )
import Cardano.Wallet.Network
    ( NetworkLayer (..)
    )
import Cardano.Wallet.Network.RestorationMode
    ( RestorationPoint (..)
    )
import Cardano.Wallet.Primitive.Model
    ( initWallet
    )
import Cardano.Wallet.Primitive.NetworkId
    ( NetworkDiscriminant (..)
    )
import Cardano.Wallet.Primitive.Passphrase
    ( Passphrase (..)
    , PassphraseScheme (..)
    , WalletPassphraseInfo (..)
    )
import Cardano.Wallet.Primitive.SyncProgress
    ( SyncProgress (..)
    )
import Cardano.Wallet.Primitive.Types
    ( ActiveSlotCoefficient (..)
    , WalletId (..)
    , WalletMetadata (..)
    , WalletName (..)
    )
import Cardano.Wallet.Primitive.Types.Address
    ( Address
    )
import Cardano.Wallet.Primitive.Types.Coin
    ( Coin (..)
    )
import Cardano.Wallet.Primitive.Types.Credentials
    ( RootCredentials (..)
    )
import Cardano.Wallet.Primitive.Types.RewardAccount
    ( RewardAccount
    )
import Cardano.Wallet.Primitive.Types.Tx.SealedTx
    ( SealedTx
    )
import Cardano.Wallet.Shelley.Transaction
    ( newTransactionLayer
    )
import Cardano.Wallet.TokenMetadata
    ( newMetadataClient
    )
import Cardano.Wallet.Transaction
    ( TransactionLayer
    )
import Cardano.Wallet.Unsafe
    ( someDummyMnemonic
    )
import Control.Concurrent.Concierge
    ( newConcierge
    )
import Control.Lens
    ( (^.)
    )
import Control.Tracer
    ( nullTracer
    )
import Cryptography.Hash.Core
    ( hash
    )
import Data.ByteString
    ( ByteString
    )
import Data.Proxy
    ( Proxy (..)
    )
import Servant.Server
    ( runHandler
    )
import System.IO.Temp
    ( withSystemTempDirectory
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )
import Prelude

import qualified Cardano.Api as Cardano
import qualified Cardano.Wallet.Address.Derivation.Byron as Byron
import qualified Cardano.Wallet.Read as Read
import qualified Cardano.Wallet.Registry as Registry
import qualified Data.Map.Strict as Map

spec :: Spec
spec = describe "A wallet whose worker has exited" $ do
    describe "Shelley" $ do
        it "is listed with the state not_responding"
            $ withDeadWallet shelleyFixture
            $ \fx -> do
                ws <- runHandler' $ listWallets (ctx fx) mkShelleyWallet
                map (stateOf . fst) ws `shouldBe` [NotResponding]
        it "is returned by get with the state not_responding"
            $ withDeadWallet shelleyFixture
            $ \fx -> do
                (w, _) <-
                    runHandler' $ getWallet (ctx fx) mkShelleyWallet (ApiT (wid fx))
                stateOf w `shouldBe` NotResponding
    describe "Shared" $ do
        it "is listed with the state not_responding"
            $ withDeadWallet sharedFixture
            $ \fx -> do
                ws <- runHandler' $ listWallets (ctx fx) mkSharedWallet
                map (sharedStateOf . fst) ws `shouldBe` [Just NotResponding]
        it "is returned by get with the state not_responding"
            $ withDeadWallet sharedFixture
            $ \fx -> do
                (w, _) <-
                    runHandler' $ getWallet (ctx fx) mkSharedWallet (ApiT (wid fx))
                sharedStateOf w `shouldBe` Just NotResponding
    describe "Byron with an Argon2id V2 passphrase" $ do
        it "is listed with the state not_responding"
            $ withDeadWallet byronFixture
            $ \fx -> do
                ws <- runHandler' $ listWallets (ctx fx) mkLegacyWallet
                map (stateOf' . fst) ws `shouldBe` [NotResponding]
        it "is returned by get with the state not_responding"
            $ withDeadWallet byronFixture
            $ \fx -> do
                (w, _) <-
                    runHandler' $ getWallet (ctx fx) mkLegacyWallet (ApiT (wid fx))
                stateOf' w `shouldBe` NotResponding
  where
    stateOf :: ApiWallet -> SyncProgress
    stateOf w = getApiT (w ^. #state)

    stateOf' :: ApiByronWallet -> SyncProgress
    stateOf' w = getApiT (w ^. #state)

    sharedStateOf :: ApiSharedWallet -> Maybe SyncProgress
    sharedStateOf = \case
        ApiSharedWallet (Right (w :: ApiActiveSharedWallet)) ->
            Just $ getApiT (w ^. #state)
        ApiSharedWallet (Left _) -> Nothing

    runHandler' h =
        runHandler h >>= either (fail . show) pure

{-------------------------------------------------------------------------------
    Fixture
-------------------------------------------------------------------------------}

-- | An API layer with an empty worker registry over a directory that holds
-- the database of one wallet, so that the wallet's worker is gone.
data Fixture s = Fixture
    { ctx :: ApiLayer s
    , factory :: DBFactory IO s
    , wid :: WalletId
    }

-- | Flavor, transaction layer and database parameters of a test wallet.
data Wallet s
    = Wallet
        (WalletFlavorS s)
        (TransactionLayer (KeyOf s) (CredFromOf s) SealedTx)
        (DBLayerParams s)

withDeadWallet
    :: forall s a
     . PersistAddressBook s
    => Wallet s
    -> (Fixture s -> IO a)
    -> IO a
withDeadWallet (Wallet wf tl ps) action =
    withSystemTempDirectory "dead-wallet" $ \tmp -> do
        let walletId = WalletId (hash ("dead-wallet" :: ByteString))
            mk = do
                df <-
                    newDBFactory
                        wf
                        nullTracer
                        defaultFieldValues
                        dummyTimeInterpreter
                        (Just tmp)
                registry <- Registry.empty
                tokenMetadata <- newMetadataClient nullTracer Nothing
                locks <- newConcierge
                let api =
                        ApiLayer
                            nullTracer
                            nullTracer
                            (block0, dummyNetworkParameters)
                            networkLayer
                            tl
                            df
                            registry
                            locks
                            tokenMetadata
                pure
                    Fixture
                        { ctx = api
                        , factory = df
                        , wid = walletId
                        }
        fx <- mk
        withDatabaseBoot (factory fx) walletId ps (\_ -> pure ())
        action fx
  where
    networkLayer =
        dummyNetworkLayer
            { timeInterpreter = dummyTimeInterpreter
            , currentNodeTip = pure Read.GenesisTip
            }

shelleyFixture :: Wallet (SeqState 'Mainnet ShelleyKey)
shelleyFixture =
    Wallet
        ShelleyWallet
        (newTransactionLayer ShelleyKeyS Cardano.Mainnet)
        (dbParams state Nothing)
  where
    state =
        mkSeqStateFromRootXPrv
            ShelleyKeyS
            (RootCredentials rootXPrv mempty)
            purposeCIP1852
            defaultAddressPoolGap
            IncreasingChangeAddresses

sharedFixture :: Wallet (SharedState 'Mainnet SharedKey)
sharedFixture =
    Wallet
        SharedWallet
        (newTransactionLayer SharedKeyS Cardano.Mainnet)
        (dbParams state Nothing)
  where
    accXPub = toXPub (getKey rootXPrv)
    template =
        ScriptTemplate
            (Map.fromList [(Cosigner 0, accXPub)])
            (RequireAllOf [RequireSignatureOf (Cosigner 0)])
    state =
        mkSharedStateFromAccountXPub
            SharedKeyS
            (SharedKey accXPub)
            minBound
            IncreasingChangeAddresses
            defaultAddressPoolGap
            template
            Nothing

byronFixture :: Wallet (RndState 'Mainnet)
byronFixture =
    Wallet
        ByronWallet
        (newTransactionLayer ByronKeyS Cardano.Mainnet)
        (dbParams state (Just argon2))
  where
    state = mkRndState byronKey 0
    byronKey :: ByronKey 'RootK XPrv
    byronKey = Byron.generateKeyFromSeed mnemonic (Passphrase mempty)
    argon2 = WalletPassphraseInfo epoch EncryptWithArgon2idV2
    epoch = read "2026-01-01 00:00:00 UTC"

dbParams
    :: forall s
     . (IsOurs s Address, IsOurs s RewardAccount)
    => s
    -> Maybe WalletPassphraseInfo
    -> DBLayerParams s
dbParams state passphraseInfo =
    DBLayerParams
        (snd $ initWallet block0 state)
        RestorationPointAtGenesis
        WalletMetadata
            { name = WalletName "dead wallet"
            , creationTime = read "2026-01-01 00:00:00 UTC"
            , passphraseInfo
            }
        mempty
        dummyGenesisParameters

mnemonic :: SomeMnemonic
mnemonic = someDummyMnemonic (Proxy @15)

rootXPrv :: ShelleyKey 'RootK XPrv
rootXPrv = generateKeyFromSeed (mnemonic, Nothing) mempty

defaultFieldValues :: DefaultFieldValues
defaultFieldValues =
    DefaultFieldValues
        { defaultActiveSlotCoefficient = ActiveSlotCoefficient 1.0
        , defaultDesiredNumberOfPool = 0
        , defaultMinimumUTxOValue = Coin 1_000_000
        , defaultHardforkEpoch = Nothing
        , defaultKeyDeposit = Coin 2_000_000
        }

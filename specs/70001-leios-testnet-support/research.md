# Research: Leios Testnet Support

**Status**: SRP commits known (from leios-prototype branch). Phase A can begin.
**Last updated**: 2026-08-13

---

## 1. What is Linear Leios?

**Linear Leios** (CIP-164) is shipped as part of **DijkstraEra** (Protocol
Version 12, Phase 1, targeting Q4 2026). It introduces two block types alongside
standard Praos block production:

| Block type | Producer | Frequency | Purpose |
|---|---|---|---|
| Endorser Block (EB) | SPO committee | Under load, higher than RBs | References additional transactions |
| Ranking Block (RB) | Slot leader (Praos) | Low (like today) | Canonical chain |

EBs are produced and certified **when there is enough transaction load to warrant
them**. They contain **references to transactions**, not transaction bodies
directly. A stake-based committee votes on each EB; when enough votes accumulate
to form a certificate (75% quorum of aggregated BLS12-381 signatures), the
certified EB is adopted into chain selection. The certificate (containing the EB
hash + aggregated signatures) is included in a Ranking Block, anchoring those
transactions into the canonical chain.

"Linear" refers to the linear ordering of EBs — each EB extends the previous EB
rather than referencing an arbitrary set of Input Blocks (which do not exist in
this design).

A transaction is **confirmed** when:
1. An EB referencing the transaction is certified by committee quorum, and
2. The RB containing that certificate reaches finality.

### Dijkstra Phase 1 — full feature set (Q4 2026)

Linear Leios is one of several changes in DijkstraEra Phase 1:

| CIP | Feature | Wallet impact |
|---|---|---|
| CIP-164 | Linear Leios (RBs + EBs) | Block sync, N2C versions |
| CIP-167 | Remove `isValid` field | Transaction parsing changes |
| CIP-176 | Non-segregated block body serialization | Block body parsing |
| CIP-118 | Nested transactions | Out of scope (testnet milestone) |
| CIP-112 | Observe Script / Guard Scripts | Out of scope |
| CIP-159 | Account Address Enhancement Phase 1 | TBD |
| CIP-181 | Remove DRep requirement for reward withdrawals | Minor |
| CIP-50 | Pledge leverage staking rewards | Out of scope |

**Phase 2** (Q2 2027, intra-era): Peras activation (CIP-140) — adds a voting
overlay to Praos chain selection for faster settlement. Out of scope here.

### Wallet backend impact

The wallet communicates via **Node-to-Client (N2C)** only:

- `ChainSync`: streams canonical chain (RBs with embedded EB certificates)
- `LocalStateQuery`: UTxO, protocol params, rewards
- `LocalTxSubmission`: submit transactions to mempool → picked up by next EB

The wallet does **not** participate in EB production or committee voting. From
the wallet's perspective the key question is whether N2C ChainSync exposes:

- (a) RBs only (EB-referenced transactions appear aggregated in the RB body), or
- (b) RBs with EB references, requiring the wallet to also fetch EB bodies

This determines whether any new block-processing code is needed beyond extending
`nodeToClientVersions`.

### Leios is NOT a new ledger era (confirmed)

Based on `cardano-api-11.x` (CHaP-indexed) and `cardano-ledger-dijkstra-0.1.0.0`:

- No `LeiosEra` type exists in any indexed package
- `cardano-api-11.0.0.0` introduces **BLS12-381 key types** (`BlsKey`,
  `BlsPossessionProof`) for SPO participation in the Leios voting/endorsement
  scheme — but these are addons to the Dijkstra era, not a new era
- The certificate type remains `DijkstraTxCert` — no `LeiosTxCert` yet

Leios is a **protocol-level** upgrade within the Dijkstra era: SPOs register
an additional BLS key via an on-chain certificate, then participate in EB
production and voting. The ledger state, UTxO model, and transaction format
are unchanged.

---

## 2. Current Dependency State (master branch)

**Production era context**: The Cardano mainnet is currently in **Conway** era.
DijkstraEra is implemented in the codebase but is behind the
`ExperimentalHardForks` feature flag in the node — not yet activated on mainnet.
The Leios testnet will run with `ExperimentalHardForks` enabled, hard-forking
through Conway → Dijkstra → Leios protocol activation.

Master is **already at** `cardano-api 11.0.0.0` / `ouroboros-consensus 3.0.1.0`.
The large dependency jump (from 10.x to 11.x) has already happened. Key versions
as of master:

| Package | Version in master |
|---|---|
| `cardano-api` | 11.0.0.0 |
| `cardano-cli` | 11.0.0.0 |
| `ouroboros-consensus` | 3.0.1.0 |
| `ouroboros-network` | 1.1.0.0 |
| `typed-protocols` | 1.2.1.0 |
| `network-mux` | 0.10.1.0 |

The target node version is **cardano-node 11.1.0.164** (Leios prototype build;
the `.164` suffix matches the testnet network magic). This is a minor version
bump from `11.0.0.0` — a freeze file will clarify the exact dependency versions
required.

### Musashi Dōjō connection details

**Musashi Dōjō** is the official name of the Leios testnet ("the testnet and
training hall for Ouroboros Leios"). Currently in its Water phase (began
2026-08-11).

| Detail | Value |
|---|---|
| Network magic | `164` |
| Bootstrap relay | `leios-node.play.dev.cardano.org:3001` |
| Faucet | `faucet.leios.play.dev.cardano.org/basic-faucet` |
| Docker image | `ghcr.io/input-output-hk/ouroboros-leios/cardano-node-testnet:prototype-2026w30` |

### What cardano-api 11.x adds

`cardano-api-11.0.0.0` (CHaP, indexed) exposes:

- `Cardano.Api.Key.Internal.Leios`:
  - `BlsKey` — BLS12-381 key type for Leios SPO participation
  - `BlsPossessionProof` — proves BLS key ownership before registration
  - `createBlsPossessionProof`, `minSigPoPContext`
- These are new types not yet wired into the wallet — they are needed when
  implementing BLS key registration certificate support

`ouroboros-consensus 3.0.1.0` (major version bump that landed in master):
- Merged all sublibraries: use `ouroboros-consensus:{cardano, diffusion, ...}` syntax
- `cardano-api-11.x` already uses `ouroboros-consensus ^>=3.0`

### SRP Pins (from node's leios-prototype cabal.project)

The `leios-prototype` branch of `IntersectMBO/cardano-node` pins these SRPs.
The wallet must use the same commits. Dijkstra ledger code is **not yet on CHaP**
(`eras/dijkstra/impl` is in the `cardano-ledger` SRP) — the SRP is mandatory.

| Repo | Commit | Notes |
|---|---|---|
| `IntersectMBO/ouroboros-consensus` | `6dc84b8f...` | Replaces CHaP `3.0.1.0` |
| `IntersectMBO/typed-protocols` | `9b462722...` | |
| `IntersectMBO/cardano-ledger` | `f3104f00...` | Includes `eras/dijkstra/impl` |
| `IntersectMBO/ouroboros-network` | `4b3ab766...` | |
| `IntersectMBO/cardano-api` | `f5ee53d4...` | Includes `cardano-rpc` (new) |
| `IntersectMBO/cardano-cli` | `de786557...` | |
| `input-output-hk/kes-agent` | `4e7ec7b5...` | |
| `input-output-hk/ekg-forward` | `85470ae7...` | |
| `IntersectMBO/cardano-base` | `9c6078d9...` | Includes `cardano-crypto-leios` (new) |

Node index-state (target for wallet update):
- `hackage.haskell.org 2026-07-15T21:58:35Z`
- `cardano-haskell-packages 2026-07-27T20:44:57Z`

**Wallet-specific SRPs** (not in node's cabal.project — may need tag bumps):
- `cardano-foundation/cardano-ledger-read` — current `0ce0e7a8...`; likely needs bump
- `cardano-foundation/cardano-balance-transaction` — current `964e8a23...`; likely needs bump
- `cardano-foundation/cardano-coin-selection` — current `176611048...`; may be no-op

---

## 3. Dijkstra Wiring Audit (actual code state)

The Dijkstra wiring is **partial**. Some layers are fully wired; others still
have `error` stubs or catch-all patterns that stop at Conway. The Leios testnet
traverses Conway → Dijkstra before Leios activates, so every stub below is a
runtime panic waiting to happen.

### Already wired (no changes needed)

| File | What's done |
|---|---|
| `lib/network-layer/src/Cardano/Wallet/Network/LocalStateQuery/Extra.hs` | `onAnyEra` / `onAnyEra'` take 8 params, Dijkstra fully included |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Shelley.hs` | `fromDijkstraPParams` fully implemented |
| `lib/wallet/src/Cardano/Wallet.hs` — `pparamsInRecentEra` | Dijkstra arm present and implemented |

### Needs Dijkstra wiring

#### Network layer

| File | What to fix |
|---|---|
| `lib/network-layer/src/Cardano/Wallet/Network/Implementation.hs` | `codecConfig` has 8 `ShelleyCodecConfig`s (last = Conway); add a 9th for Dijkstra |
| `lib/network-layer/src/Cardano/Wallet/Network/Implementation.hs` | `_getUTxOByTxIn` — error stub for Dijkstra |
| `lib/network-layer/src/Cardano/Wallet/Network/LocalStateQuery/UTxO.hs` | `getUTxOByTxIn` — Dijkstra case missing |

#### API layer

| File | What to fix |
|---|---|
| `lib/api/src/Cardano/Wallet/Api/Types/Era.hs` | `fromReadEra`: `Dijkstra -> error "not yet supported"` — add `ApiDijkstra` |
| `lib/api/src/Cardano/Wallet/Api/Types/Era.hs` | `fromAnyCardanoEra`: same — `DijkstraEra -> error` |

#### Primitive / Read layer

| File | What to fix |
|---|---|
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Read/Eras.hs` | `fromAnyCardanoEra`: catch-all `_ -> error` after Conway — add explicit Dijkstra case |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Convert.hs` | `toWalletScript` — Dijkstra script constructors |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Read/Tx/Features/Outputs.hs` | `txOutFromOutput` — Dijkstra case using `fromDijkstraTxOut` |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Read/Tx/Sealed.hs` | `fromCardanoApiTx` — Dijkstra case |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Read/Tx/TxExtended.hs` | `fromCardanoTx` — Dijkstra case |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Shelley.hs` | `toCardanoEra` — `Dijkstra -> DijkstraEra` missing |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Shelley.hs` | `forAllBlocks` — `BlockDijkstra -> error "not yet supported"` |

#### Balance-tx layer

| File | What to fix |
|---|---|
| `lib/balance-tx/lib/internal/Internal/Cardano/Write/Tx.hs` | `upgradeToOutputConway` — Dijkstra downgrade case |

#### Wallet core

| File | What to fix |
|---|---|
| `lib/wallet/src/Cardano/Wallet/Pools.hs` | `forAllBlocks`: `BlockDijkstra _ -> error "not yet supported"` |
| `lib/wallet/src/Cardano/Wallet/Shelley/Transaction.hs` | Various `_ -> error` wildcard arms for Dijkstra |

#### Deprecation cleanups

Three files suppress `{-# OPTIONS_GHC -Wno-deprecations #-}` and need
migration from `Cardano.Api.Certificate` to
`Cardano.Api.Experimental.Certificate`:

- `lib/wallet/src/Cardano/Wallet/Shelley/Transaction.hs`
- `lib/wallet/src/Cardano/Wallet/Transaction/Delegation.hs`
- `lib/wallet/src/Cardano/Wallet/Transaction/Voting.hs`

---

## 4. Leios-Specific Changes (Protocol Extension within Dijkstra)

Since Leios is not a new era, the wallet changes for Leios support are:

### 4.1 N2C Protocol Version Extension

Current `nodeToClientVersions` in `Shelley.hs`:

```haskell
nodeToClientVersions = [V_16 .. V_22]
```

Extended to `[V_16, V_17]` → `[V_16 .. V_22]` for Dijkstra (ERA-CHANGES.md §3.5).
Node 11.1.0.164 will require a higher version. Exact range TBD from freeze file.

### 4.2 Dijkstra Genesis File

The Leios testnet uses a single `dijkstra-genesis.json` for both the Dijkstra
hard fork and any Leios protocol parameters — no additional genesis files are
needed. The local cluster tooling already references `dijkstra-genesis.json`;
the work is ensuring it is correctly supplied and complete for the testnet.
Files to verify:

- `lib/local-cluster/lib/Cardano/Wallet/Launch/Cluster/Node/GenesisFiles.hs`
- `lib/local-cluster/lib/Cardano/Wallet/Launch/Cluster/Node/GenNodeConfig.hs`
- `configs/` testnet YAML/JSON files

### 4.3 BLS Key Registration (out of scope for testnet milestone)

SPOs register BLS keys via a new certificate type. The `cardano-api-11.x`
`BlsKey` / `BlsPossessionProof` types are available but the wallet does not
need to construct or validate these certificates for basic testnet operation
(balance query, transaction submission). This is explicitly out of scope.

### 4.4 Linear Leios Block Structure

If node 11.1.0.164 exposes EB references separately via N2C ChainSync (rather
than embedding EB-certified transactions in the RB body), the wallet will need
new block processing for EB content. This is TBD until the node source is
available. The most likely case is that EB-certified transactions appear
aggregated in the canonical chain via the RB certificate, and the wallet sees
only RBs as today.

---

## 5. Open Questions (to resolve with freeze file / node source)

1. **Does N2C ChainSync for node 11.1.0.164 expose EB references separately**,
   or are EB-certified transactions aggregated into the RB body for chain-following
   clients?

2. **What N2C protocol versions does node 11.1.0.164 require?**
   Needed to extend `nodeToClientVersions`.

3. **What fields does `dijkstra-genesis.json` need for Leios protocol activation?**
   This single genesis file covers both the Dijkstra hard fork and any Leios
   protocol parameters — no additional genesis files are required.

4. **What changed between cardano-api 11.0.0.0 and 11.1.x?**
   The freeze file will tell us the exact versions required — this is a minor
   version bump, not a patch, so more may have changed than a typical patch.

5. **Do the existing SRP pins (`cardano-ledger-read`, `cardano-balance-tx`)
   need updates for node 11.1.0.164?**
   Likely yes — the SRP commit list will confirm.

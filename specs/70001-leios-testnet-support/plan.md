# Implementation Plan: Leios Testnet Support

**Branch**: `70001-leios-testnet-support` | **Date**: 2026-08-13 | **Spec**: [spec.md](spec.md)
**Status**: Skeleton — Phase A can start immediately; Phase B unblocked (SRP commits known from node repo).

---

## Context

- **Production era**: Conway. Dijkstra is experimental (`ExperimentalHardForks`).
- **Master**: already at `cardano-api 11.0.0.0` / `ouroboros-consensus 3.0.1.0`.
  Target node is **11.1.0.164** (Leios prototype) — a minor version bump from master.
- **Linear Leios**: no Input Blocks; transactions in EBs → RBs. Leios is a
  protocol extension within DijkstraEra, **not a new ledger era** — no new era
  wiring phase needed.

## Summary

Bring the wallet backend to a state where it connects to and operates against
the Leios testnet. The work has two sequential phases (Phase C dropped — Leios
is not a new era):

1. **Phase A — Dijkstra promotion**: Implement all 16 Dijkstra `error` stubs.
   The Leios testnet goes Conway → Dijkstra → Leios; without these the wallet
   panics at the Dijkstra hard-fork boundary.

2. **Phase B — Dependency bump + upstream repo updates**: Add SRPs from the node's
   `leios-prototype` branch. Update `cardano-ledger-read` (no Dijkstra yet) and
   `cardano-balance-transaction` (Dijkstra at old CHaP version) to compile against
   the new SRP set. Verify `cardano-coin-selection` still builds unchanged. Extend
   `nodeToClientVersions`, update flake to `leios-prototype`, verify connectivity.

---

## Technical Context

**Language/Version**: Haskell, GHC 9.12
**Base**: master at `cardano-api 11.0.0.0`, `ouroboros-consensus 3.0.1.0`
**Target**: cardano-node 11.1.0.164 (Leios prototype; freeze file + SRP list pending)
**Testing**: `cabal build all -O0`, local Leios testnet node smoke test
**Constraints**: Must not break Byron–Dijkstra processing; Leios-era advanced
features (BLS key cert construction, EB-specific queries) are out of scope for
the testnet milestone.

---

## Phase A — Promote Dijkstra to RecentEra

*Can begin immediately — no freeze file needed.*

### A.1 — API layer (`lib/api/`)

**File**: `src/Cardano/Wallet/Api/Types/Era.hs`

Add `ApiDijkstra` constructor:

```haskell
fromReadEra :: Read.Era era -> Maybe ApiEra
fromReadEra = \case
    Read.Byron    -> Just ApiBabylon  -- existing
    ...
    Read.Dijkstra -> Just ApiDijkstra -- ADD

fromAnyCardanoEra :: AnyCardanoEra -> Maybe ApiEra
fromAnyCardanoEra = \case
    ...
    AnyCardanoEra DijkstraEra -> Just ApiDijkstra -- ADD
```

### A.2 — Balance-tx layer (`lib/balance-tx/`)

**File**: `lib/internal/Internal/Cardano/Write/Tx.hs`

`upgradeToOutputConway`: add Dijkstra downgrade case (same as Conway pattern —
`BabbageTxOut` is shared between Conway and Dijkstra).

### A.3 — Network layer (`lib/network-layer/`)

**File**: `src/Cardano/Wallet/Network/Implementation.hs`

`_getUTxOByTxIn`: use `QueryIfCurrentDijkstra GetUTxOByTxIn` (same query
struct as Conway, `QueryIfCurrentConway`).

**File**: `src/Cardano/Wallet/Network/LocalStateQuery/UTxO.hs`

`getUTxOByTxIn`: add Dijkstra case using `QueryIfCurrentDijkstra`.

### A.4 — Primitive layer (`lib/primitive/`)

**File**: `lib/Cardano/Wallet/Primitive/Ledger/Convert.hs`

`toWalletScript`: catch remaining Dijkstra timelock/native script constructors.

**File**: `lib/Cardano/Wallet/Primitive/Ledger/Read/Eras.hs`

`fromAnyCardanoEra`: add `DijkstraEra -> ...` case.

**File**: `lib/Cardano/Wallet/Primitive/Ledger/Read/Tx/Features/Outputs.hs`

`txOutFromOutput`: add Dijkstra case using `fromDijkstraTxOut` (already exists
in `cardano-wallet-read`).

**File**: `lib/Cardano/Wallet/Primitive/Ledger/Read/Tx/Sealed.hs`

`fromCardanoApiTx`: add Dijkstra case (same pattern as Conway).

**File**: `lib/Cardano/Wallet/Primitive/Ledger/Read/Tx/TxExtended.hs`

`fromCardanoTx`: add Dijkstra case.

**File**: `lib/Cardano/Wallet/Primitive/Ledger/Shelley.hs`

- `toCardanoEra`: add `Dijkstra -> DijkstraEra`
- `forAllBlocks`: implement `BlockDijkstra` processing (same pattern as
  `BlockConway` — extract from `ShelleyBlock`)

### A.5 — Wallet core (`lib/wallet/`)

**File**: `src/Cardano/Wallet.hs`

`pparamsInRecentEra`: add Dijkstra case using `fromDijkstraPParams` (already in
`cardano-wallet-primitive`).

**File**: `src/Cardano/Wallet/Pools.hs`

`withRecentEraLedgerTx`: add Dijkstra case.

**File**: `src/Cardano/Wallet/Shelley/Transaction.hs`

Fill all `_ -> error "Dijkstra"` wildcard arms.

### A.6 — Deprecation cleanup

Migrate three files from `Cardano.Api.Certificate` to
`Cardano.Api.Experimental.Certificate` and remove `-Wno-deprecations`:

- `lib/wallet/src/Cardano/Wallet/Shelley/Transaction.hs`
- `lib/wallet/src/Cardano/Wallet/Transaction/Delegation.hs`
- `lib/wallet/src/Cardano/Wallet/Transaction/Voting.hs`

### A.7 — Remove TODO.md entries

Once all stubs above are implemented, remove the resolved entries from `TODO.md`.

---

## Phase B — Dependency Bump

Source of truth: `IntersectMBO/cardano-node` branch `leios-prototype`, file
`cabal.project`. All SRP commits and index-state values come from there.

### B.0 — Index-state update

Current wallet:
```
hackage.haskell.org     2026-02-17T10:15:41Z
cardano-haskell-packages 2026-03-23T18:21:55Z
```

Node `leios-prototype`:
```
hackage.haskell.org     2026-07-15T21:58:35Z
cardano-haskell-packages 2026-07-27T20:44:57Z
```

Update both timestamps in `cabal.project`.

### B.1 — SRPs to add from node's cabal.project

The following packages are pinned as SRPs in `leios-prototype/cabal.project`.
The wallet must use the **same commits** to avoid version conflicts. Add each as
a `source-repository-package` block in the wallet's `cabal.project`, keeping
only the subdirs the wallet actually depends on (trim `cardano-api-gen`,
`cardano-rpc`, `cardano-cli`, `kes-agent` if the wallet doesn't import them):

| Package / repo | Commit | Subdirs |
|---|---|---|
| `IntersectMBO/ouroboros-consensus` | `6dc84b8fead9226dada19ca26d8eb59e0000c388` | (all) |
| `IntersectMBO/typed-protocols` | `9b4627221ae5d649f2303c6926a8dba3f9934658` | `typed-protocols` |
| `IntersectMBO/cardano-ledger` | `f3104f00f9819ba94de119c38bc3e0109982821f` | `libs/cardano-data`, `libs/cardano-ledger-api`, `libs/small-steps`, `libs/cardano-ledger-binary`, `libs/cardano-ledger-core`, `libs/cardano-protocol-tpraos`, `eras/byron/crypto`, `eras/shelley/impl`, `eras/shelley-ma/test-suite`, `eras/mary/impl`, `eras/allegra/impl`, `eras/alonzo/impl`, `eras/alonzo/test-suite`, `eras/babbage/impl`, `eras/conway/impl`, `eras/dijkstra/impl` |
| `IntersectMBO/ouroboros-network` | `4b3ab7664f609a1aee0f0c24dcfcfd0ab899fc42` | `ouroboros-network`, `cardano-diffusion`, `network-mux` |
| `IntersectMBO/cardano-api` | `f5ee53d4c26bd0d36540a2a6d06899ff9376aa9b` | `cardano-api` (+ `cardano-api-gen`, `cardano-rpc` if needed) |
| `IntersectMBO/cardano-cli` | `de786557757db816af2dcf56b0a667cecfced011` | `cardano-cli` (if needed) |
| `input-output-hk/kes-agent` | `4e7ec7b5102a030587413f4af770e87a15c9cb9c` | `kes-agent`, `kes-agent-crypto` (if needed) |
| `input-output-hk/ekg-forward` | `85470ae7e8fac9711682234ed39a36eec3d45a9b` | (all) |
| `IntersectMBO/cardano-base` | `9c6078d9c39c542abcb5912d0d7c222b7ba8a03d` | `cardano-binary`, `cardano-crypto-class`, `cardano-crypto-praos`, `cardano-crypto-leios` |

Note: `cardano-crypto-leios` is a **new subdir** in `cardano-base` for BLS12-381
Leios crypto. The wallet needs it transitively for `cardano-api`.

### B.2 — SRP for cardano-node itself

Add an SRP for `IntersectMBO/cardano-node` at the `leios-prototype` branch HEAD.
This gives the wallet access to node types/utilities used transitively:

```cabal
source-repository-package
  type: git
  location: https://github.com/IntersectMBO/cardano-node
  tag: <leios-prototype HEAD commit>
  subdir: cardano-node  -- trim to what wallet imports
```

Determine the exact commit with:
```bash
git ls-remote https://github.com/IntersectMBO/cardano-node leios-prototype
```

### B.3 — Upstream repo updates (cardano-foundation)

These three repos are pinned in the wallet as SRPs but need upstream changes
before we can update the wallet's pins. All three are currently on `main` at
CHaP `2026-05-02` / `ouroboros-consensus 3.0.1.0`. Work happens in their own
repos; wallet pin update follows once PRs merge.

#### B.3.1 — `cardano-foundation/cardano-ledger-read` (current `0ce0e7a8...`)

**Problem**: has no `cardano-ledger-dijkstra` dependency at all. Wallet depends
on this for reading ledger state — Dijkstra support must be added before the
wallet can query UTxOs in the Dijkstra era.

**Work**:
1. Add `cardano-ledger-dijkstra` as a dependency in the `.cabal` file
2. Implement a `Read.Dijkstra` era instance (following the Conway pattern)
3. Add all 9 SRPs from the node's `leios-prototype` `cabal.project` to its own `cabal.project`
4. Bump index-state to `hackage 2026-07-15` / `CHaP 2026-07-27`
5. Verify it builds; open PR to `main`
6. Pin the merged commit in the wallet's `cabal.project`

#### B.3.2 — `cardano-foundation/cardano-balance-transaction` (current `964e8a23...`)

**Problem**: pins `cardano-ledger-dijkstra == 0.2.0.1` from CHaP, but the node's
SRP provides a newer unreleased commit of `cardano-ledger-dijkstra`. The CHaP
version will conflict with the SRP version.

**Work**:
1. Replace the CHaP `cardano-ledger-dijkstra` constraint with the SRP from the node
2. Add remaining SRPs from the node's `leios-prototype` `cabal.project`
3. Bump index-state to `hackage 2026-07-15` / `CHaP 2026-07-27`
4. Fix any API breakage from the new dijkstra version
5. Verify it builds; open PR to `main`
6. Pin the merged commit in the wallet's `cabal.project`

#### B.3.3 — `cardano-foundation/cardano-coin-selection` (current `176611048...`)

**Problem**: very minimal `cabal.project` (`index-state: 2025-10-01`), does not
depend on `cardano-ledger` directly. Likely no-op but must be verified.

**Work**:
1. Attempt `cabal build` against the new SRP set
2. If it fails, add relevant SRPs and fix breakage; open PR
3. If it passes, no upstream PR needed — existing wallet pin remains valid

### B.4 — Constraints block

Node's `leios-prototype` constraints to add/merge into wallet `cabal.project`:

```cabal
constraints:
  , any.crypton < 1.1
  , any.crypton-x509-system < 1.6.8
  , any.proto-lens >= 0.7.1.7
  , any.alfred-margaret < 2.1.1.0 || > 2.1.1.0
```

### B.5 — Flake update

```
# flake.nix: change
cardano-node-runtime.url = "github:IntersectMBO/cardano-node?ref=10.7.1";
# to
cardano-node-runtime.url = "github:IntersectMBO/cardano-node?ref=leios-prototype";
```

Then run `nix flake update cardano-node-runtime chap` to update `flake.lock`.

### B.6 — N2C version extension

Extend `nodeToClientVersions` in `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Shelley.hs`
(currently `[V_16 .. V_22]`) to cover the version(s) required by `11.1.0.164`.
Exact range determined by checking `NodeToClientVersion` in the pinned
`ouroboros-consensus` commit.

### B.7 — Build and iterate

```bash
nix develop -c cabal build all -O0 2>&1 | head -100
```

Iterate until clean. Compilation errors will reveal:
- Missing version bounds in `.cabal` files
- API changes in `cardano-api` `11.1.x` vs `11.0.0.0`
- Any new Dijkstra/Leios types that need handling

### B.8 — What to expect from the 11.0.x → 11.1.x bump

This is a minor version bump, not a patch. Known additions from the node's SRPs:
- `cardano-crypto-leios` (new BLS12-381 sublib in `cardano-base`)
- `cardano-rpc` (new subdir in `cardano-api` — RPC interface for the node)
- `eras/dijkstra/impl` now in `cardano-ledger` SRP — confirms Dijkstra ledger
  code is not yet on CHaP (so the SRP is required, not optional)

### B.9 — Known risk areas

| Risk | Mitigation |
|---|---|
| New transitive constraints missing | Add any `cabal build` reports |
| SRP pins lagging ledger versions | Verify SRP commits compile with new versions |
| `cardano-api` re-introduced transitively | Check build plan; flag for `001-drop-cardano-api` |
| New N2C message types for EBs | Assess if ChainSync needs EB handling; likely not for wallet clients |

---

## Process Notes

### Build-test loop

```bash
nix develop -c cabal build all -O0 2>&1 | head -50
```

Iterate until clean. Then:

```bash
nix develop -c cabal test cardano-wallet-network-layer --test-show-details=direct
```

### Musashi Dōjō smoke test

```bash
# Option A: connect directly to the testnet relay
nix develop -c cabal run cardano-wallet -- serve \
    --node-socket /tmp/musashi/node.socket \
    --testnet /tmp/musashi/config/byron-genesis.json
# (relay: leios-node.play.dev.cardano.org:3001, network magic 164)

# Option B: run a local node via Docker first
docker run --rm -v /tmp/musashi:/data \
    ghcr.io/input-output-hk/ouroboros-leios/cardano-node-testnet:prototype-2026w30
```

---

## File Change Summary

### Phase A (Dijkstra promotion)

| File | Change type |
|---|---|
| `lib/api/src/Cardano/Wallet/Api/Types/Era.hs` | Add `ApiDijkstra` + 2 era mappings |
| `lib/balance-tx/lib/internal/Internal/Cardano/Write/Tx.hs` | Add Dijkstra downgrade arm |
| `lib/network-layer/src/Cardano/Wallet/Network/Implementation.hs` | Add Dijkstra UTxO query |
| `lib/network-layer/src/Cardano/Wallet/Network/LocalStateQuery/UTxO.hs` | Add Dijkstra UTxO query |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Convert.hs` | Add Dijkstra script arms |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Read/Eras.hs` | Add Dijkstra case |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Read/Tx/Features/Outputs.hs` | Add Dijkstra output case |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Read/Tx/Sealed.hs` | Add Dijkstra case |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Read/Tx/TxExtended.hs` | Add Dijkstra case |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Shelley.hs` | `toCardanoEra`, `forAllBlocks` |
| `lib/wallet/src/Cardano/Wallet.hs` | `pparamsInRecentEra` Dijkstra |
| `lib/wallet/src/Cardano/Wallet/Pools.hs` | `withRecentEraLedgerTx` Dijkstra |
| `lib/wallet/src/Cardano/Wallet/Shelley/Transaction.hs` | Fill Dijkstra wildcards + cert migration |
| `lib/wallet/src/Cardano/Wallet/Transaction/Delegation.hs` | Cert migration |
| `lib/wallet/src/Cardano/Wallet/Transaction/Voting.hs` | Cert migration |
| `TODO.md` | Remove resolved items |

### Phase B (Dependency bump + upstream repos)

**Wallet repo (`cabal.project`, `flake.nix`):**

| File | Change type |
|---|---|
| `cabal.project` | Add 9 SRPs from node + cardano-node SRP; bump wallet-specific SRP tags; update index-state; add constraints |
| `flake.nix` | `cardano-node-runtime` input: `10.7.1` → `leios-prototype` |
| `flake.lock` | `nix flake update cardano-node-runtime chap` |
| `lib/primitive/lib/Cardano/Wallet/Primitive/Ledger/Shelley.hs` | Extend `nodeToClientVersions` |
| `lib/*/cardano-*.cabal` | Version bound updates as needed |

**Upstream repos (PRs required before wallet pin update):**

| Repo | Work | Current pin |
|---|---|---|
| `cardano-foundation/cardano-ledger-read` | Add Dijkstra support + SRPs + index-state bump | `0ce0e7a8...` |
| `cardano-foundation/cardano-balance-transaction` | Replace CHaP dijkstra `0.2.0.1` with SRP + index-state bump | `964e8a23...` |
| `cardano-foundation/cardano-coin-selection` | Verify builds; update only if broken | `176611048...` |

### Phase C (Leios era wiring — TBD)

Mirrors Phase A but for Leios. Exact files depend on whether Leios is a new era.

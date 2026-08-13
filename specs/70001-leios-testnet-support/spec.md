# Feature Specification: Leios Testnet Support

**Feature Branch**: `70001-leios-testnet-support`
**Created**: 2026-08-13
**Status**: Draft
**Input**: Bump wallet backend dependencies to support the Leios testnet. Must be able to connect, track UTxOs, and submit transactions. Correctness over polish.

## Context

**Linear Leios** is the simplified Ouroboros Leios variant deployed on the
**Musashi Dōjō** testnet ("the testnet and training hall for Ouroboros Leios",
currently in its Water phase as of 2026-08-11). Unlike the full Leios design,
there are **no Input Blocks** — Endorser Blocks (EBs) reference transactions,
which are anchored into the canonical chain via Ranking Blocks (RBs). Leios is
a **protocol-level extension within DijkstraEra**, not a new ledger era.

Target node: **cardano-node 11.1.0.164** (Leios prototype build; `.164` matches
the Musashi Dōjō network magic 164).

### Current State

- **Production era**: Conway. Dijkstra is implemented but only activates with
  `ExperimentalHardForks` enabled in the node config — not yet live on mainnet.
- **Master** is already at `cardano-api 11.0.0.0` / `ouroboros-consensus 3.0.1.0`.
  The major 10.x → 11.x dependency jump has landed. Target is node **11.1.0.164**.
- `TODO.md` catalogs 16 `error` stubs for DijkstraEra across 14 files. The Leios
  testnet traverses Conway → Dijkstra → Leios, so these stubs must be resolved
  before the wallet can sync past the Dijkstra hard-fork boundary.

### What Linear Leios Brings

| Concept | Description |
|---|---|
| Endorser Blocks (EBs) | Carry transactions directly; form a linear chain |
| Ranking Blocks (RBs) | Canonical chain; reference EBs |
| BLS keys | SPOs register BLS12-381 keys to produce/endorse EBs |

Leios is **not a new ledger era**. The UTxO model, transaction format, and
certificate structure are unchanged from Dijkstra. The wallet backend changes
are: extend `nodeToClientVersions`, handle any new genesis files, and resolve
the Dijkstra stubs so the chain sync doesn't panic on Dijkstra-era blocks on
the way to the Leios protocol activation.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Wallet connects to Musashi Dōjō (Priority: P1)

A developer starts `cardano-wallet` pointed at a Musashi Dōjō node. The wallet
establishes a connection, negotiates the protocol version, syncs chain history,
and remains live.

**Why this priority**: Without connectivity nothing else matters.

**Independent Test**: Connect wallet to Musashi Dōjō (`leios-node.play.dev.cardano.org:3001`,
network magic 164). Observe logs for successful protocol negotiation and chain tip
advancement.

**Acceptance Scenarios**:

1. **Given** a running Leios testnet node, **When** the wallet starts, **Then**
   protocol negotiation succeeds without errors.
2. **Given** a syncing wallet, **When** the chain reaches the Leios era boundary,
   **Then** the wallet continues syncing without crashing or emitting `error` panics.
3. **Given** a fully synced wallet, **When** a Leios-era block arrives, **Then**
   the wallet processes it and advances its chain tip.

---

### User Story 2 - UTxO balance is queryable (Priority: P1)

A user queries their wallet balance while the chain is in the Leios era. The
wallet returns a correct balance based on confirmed (ranking-block-included)
transactions.

**Why this priority**: Balance query is the minimum useful wallet function.

**Independent Test**: Fund an address during Leios era. Query `/wallets/:id`. Balance reflects funded amount.

**Acceptance Scenarios**:

1. **Given** an address funded in the Leios era, **When** `/wallets/:id` is
   called, **Then** the response shows the correct balance.
2. **Given** a spent output in the Leios era, **When** the wallet is queried,
   **Then** the spent output is absent from the UTxO set.

---

### User Story 3 - Transaction submission works (Priority: P2)

A user constructs and submits a simple ADA transfer via the REST API. The
transaction is submitted to the Leios node and eventually appears in a ranking
block.

**Why this priority**: Read-only is useful but submission is the core wallet
function.

**Independent Test**: POST `/wallets/:id/transactions` for a simple transfer. Poll
until confirmed.

**Acceptance Scenarios**:

1. **Given** a funded wallet in the Leios era, **When** a transaction is
   submitted, **Then** the node accepts it without a protocol error.
2. **Given** a submitted transaction, **When** enough time passes, **Then** the
   transaction appears confirmed in a ranking block and the wallet balance updates.

---

### Edge Cases

- Leios N2C protocol version may exceed the current `nodeToClientVersions` range
  — the range must be extended.
- The Leios testnet hard-forks through Dijkstra, which requires `dijkstra-genesis.json`
  — local cluster and testnet config tooling must supply it correctly.
- If Leios introduces a new era type, all era dispatch functions need a new arm
  (following the DijkstraEra wiring pattern in ERA-CHANGES.md).
- The 16 Dijkstra `error` stubs in TODO.md are a prerequisite: if Dijkstra is
  not a `RecentEra` the wallet will panic on Dijkstra-era blocks before even
  reaching Leios.
- The frozen deprecation warnings (`-Wno-deprecations` in Transaction.hs,
  Delegation.hs, Voting.hs) should be resolved as part of this work.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The wallet MUST connect to a Leios testnet cardano-node and
  negotiate N2C protocol successfully.
- **FR-002**: `cabal.project` MUST add SRPs for all packages pinned by
  `leios-prototype/cabal.project` (9 packages: ouroboros-consensus,
  typed-protocols, cardano-ledger, ouroboros-network, cardano-api, cardano-cli,
  kes-agent, ekg-forward, cardano-base + cardano-node itself) and update
  index-state to match the node's timestamps.
- **FR-003**: All 16 Dijkstra `error` stubs in `TODO.md` MUST be replaced with
  real implementations (prerequisite for Leios era support).
- **FR-004**: `nodeToClientVersions` MUST be extended to cover the N2C version(s)
  required by node `11.1.0.164`.
- **FR-005**: Local cluster genesis config tooling MUST correctly supply
  `dijkstra-genesis.json` for the Leios testnet.
- **FR-006**: Chain sync MUST process Leios-era blocks without panicking.
- **FR-007**: UTxO queries MUST return correct results in the Leios era.
- **FR-008**: Transaction submission MUST work for simple ADA transfers in the
  Leios era.
- **FR-009**: `cardano-foundation/cardano-ledger-read` MUST be updated to add
  Dijkstra era support (currently absent) and updated SRPs. A PR must be merged
  and the resulting commit pinned in the wallet's `cabal.project`.
- **FR-010**: `cardano-foundation/cardano-balance-transaction` MUST be updated
  from `cardano-ledger-dijkstra 0.2.0.1` (CHaP) to the version provided by the
  node's `cardano-ledger` SRP. A PR must be merged and the resulting commit pinned.
- **FR-011**: `cardano-foundation/cardano-coin-selection` MUST be verified to
  build against the new SRP set; updated and pinned only if it fails.

### Non-Functional Requirements

- **NFR-001**: Compilation MUST succeed with no new `error` panics for any era
  that the Leios testnet will traverse (Byron through Leios).
- **NFR-002**: `cabal build all -O0` MUST succeed in a nix develop shell.
- **NFR-003**: Advanced features (Plutus script execution in Leios era, minting,
  multi-asset, voting) are explicitly out of scope for the testnet milestone —
  `error` stubs are acceptable there.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `cabal build all -O0` succeeds with zero version conflicts against
  the node `11.1.0.164` dependency set.
- **SC-002**: Wallet connects to Musashi Dōjō (`leios-node.play.dev.cardano.org:3001`,
  network magic 164) and syncs past the Dijkstra/Leios era boundaries without panicking.
- **SC-003**: Wallet balance query returns correct results for an address funded
  on Musashi Dōjō.
- **SC-004**: Simple ADA transfer is submitted via the wallet and confirmed on
  Musashi Dōjō.
- **SC-005**: Zero remaining `error` stubs for Dijkstra era (TODO.md fully resolved).

---

## Assumptions

- SRP commits and index-state are sourced from `IntersectMBO/cardano-node`
  branch `leios-prototype` `cabal.project` — no separate freeze file needed.
- The Musashi Dōjō testnet runs the full era history (Byron → … → Dijkstra →
  Leios protocol activation) so the wallet must handle all eras in the chain.
- Leios is a protocol extension within DijkstraEra, not a new ledger era — no
  new era type wiring is required.
- `cardano-foundation/cardano-ledger-read` and `cardano-foundation/cardano-balance-transaction`
  will accept upstream PRs that add Dijkstra support; implementation does not
  require forking those repos.
- Performance and memory benchmarks are not required for the testnet milestone.

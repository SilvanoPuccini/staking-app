# Staking Protocol — STK

> A full-cycle blockchain portfolio project: from research and development
> methodology to a live, verified, and attack-tested staking protocol on
> Ethereum Sepolia — built with an AI-assisted workflow.

**Stake STK. Earn rewards. Own your yield.** This repo is a complete case study
of building, testing, hardening, and shipping a DeFi protocol — documenting
not only *what* was built, but *how* it was built and *why* it can be trusted.

» Versión en español: [README.md](README.md)

---

## 1. The story — from research to production

This project followed a structured methodology that mirrors how a real
product/engineering team would deliver a DeFi protocol:

| Phase | What happened |
|---|---|
| **1. Research** | Studied the staking domain: Synthetix `StakingRewards` accumulator design, ERC-20 token standards, reward-per-share math, common exploit classes (reentrancy, flash loans, donation inflation, griefing). |
| **2. Development schema** | Defined a spec-driven format: proposal → specs → design → tasks → apply → verify → archive (OpenSpec). Each phase has explicit inputs/outputs and acceptance criteria. |
| **3. AI-assisted build** | The plan was handed to an AI coding agent (OpenCode) with strict TDD and the schema as guardrails. The AI implemented the Solidity contracts, Foundry tests, and this documentation — *I reviewed and directed every step*. |
| **4. Analysis & hardening** | Ran the full security review below (adversarial attack suite) and invariant/fuzz testing to look for ways to corrupt the protocol. |
| **5. Skills / tooling** | The process was codified into reusable skills (smart-contract-security, foundry-testing, web3-frontend, SDD workflow) — turning one-off experience into repeatable process. |
| **6. Environment** | Foundry toolchain, local anvil chain for fast iteration, CI-style gates (fmt, build, test, coverage). |
| **7. Production** | Deployed and verified on Ethereum Sepolia testnet with a live, working frontend dApp and a real on-chain staking + claim transaction. |

**Why this matters:** the value is not the code alone — it is the *method*:
research → schema → AI execution → verification → hardening → shipping. That
is the full engineering loop this project demonstrates end-to-end.

---

## 2. What the protocol does

Two minimal contracts:

- **StakingToken (STK)** — a fixed-supply ERC-20 (10,000,000 STK, 18 decimals,
  no mint/burn after deployment).
- **StakingRewards** — a Synthetix-style staking contract: users stake STK for
  a **30-day lockup** and earn **per-second rewards** paid in STK from a
  pre-funded reward pool.

```
StakingToken (ERC-20, fixed supply)
        │ transfers / approvals
        ▼
StakingRewards (Ownable, ReentrancyGuard, SafeERC20)
  stake / withdraw / claimRewards / exit / notifyRewardAmount / recoverERC20
```

### Key mechanics

- **Stake** — deposit STK; your position locks for 30 days. Repeated stakes
  extend the whole position's lockup (design D3).
- **Earn** — rewards accrue every second via a reward-per-share accumulator
  while you are staked; claimable at any time, even during lockup. Only
  principal is locked.
- **Withdraw / Exit** — after `lockupEndOf`, withdraw principal; `exit()`
  atomically withdraws principal and claims rewards in one transaction.
- **Owner** — funds 90-day emission windows via `notifyRewardAmount()` and can
  rescue stuck external tokens via `recoverERC20()` (STK itself is excluded).

### Parameters

| Parameter | Value |
|---|---|
| `INITIAL_SUPPLY` | 10,000,000 STK |
| `REWARDS_DURATION` | 90 days (7,776,000 s) |
| `LOCKUP_DURATION` | 30 days (2,592,000 s) |
| Initial reward pool | 1,000,000 STK (10% of supply) |
| Reward rate | `min(reward + leftover, balance - totalStaked) / REWARDS_DURATION` |

---

## 3. How it was tested — 58 tests, 5 layers

| Layer | Count | What it proves |
|---|---|---|
| Unit (token) | 8 | metadata, fixed supply, no mint, transfers/allowances + reverts |
| Unit (staking) | 27 | stake/lockup, linear accrual, claim, withdraw boundary, atomic exit, notify rate/cap/owner, recoverERC20 exclusions, reentrancy, lockup extension + fuzz-style round-trip and claim-idempotence cases |
| Governance | 8 | owner = timelock, direct owner calls blocked, schedule/wait/execute flow, attacker cannot schedule/execute, recoverERC20 timelocked, hardened fix survives the timelock |
| Invariant | 5 | solvency, accounting conservation, monotonic principal, lockup integrity, rewards bounded |
| **Security attacks** | **10** | **adversarial PoCs trying to corrupt the protocol (see §4)** |

```shell
forge build                 # compile
forge test                  # full suite: 58 tests
forge fmt --check           # formatting gate
forge coverage              # ~99% lines on src/
```

The invariant suite drives the contract through 256 random sequences × 128
calls (handler-based, bounded amounts, random 0–45d time jumps) and asserts
financial-truth rules after every sequence — solvency, accounting
conservation, monotonic principal, lockup integrity, rewards bounded.

---

## 4. Security review — we tried to break it

The protocol was deliberately attacked with an **adversarial test suite**
(`test/SecurityAttack.t.sol`). Each test is a proof-of-concept for a known
attack vector. **All 10 attacks failed to corrupt the protocol** (8 blocked by
design, 2 closed by contract hardening).

| # | Attack vector | Attempt | Result |
|---|---|---|---|
| 1 | **Donation inflation** | Donate 500k STK directly to the contract to inflate `earned()` | ❌ Blocked — internal accounting (`totalStaked`), never trusts `balanceOf(this)` |
| 2 | **Flash-loan stake** | Stake 1M, claim instantly, withdraw in same block to repay loan | ❌ Blocked — 30-day lockup prevents principal withdrawal |
| 3 | **Reentrancy** | Re-enter `claimRewards` during transfer | ❌ Blocked — ReentrancyGuard + CEI ordering |
| 4 | **Lockup griefing** | Stake 1 wei to reset a victim's lockup | ❌ Blocked — lockup is per-user (`lockupEndOf[msg.sender]`) |
| 5 | **Silent reward kill** | Owner notifies below `REWARDS_DURATION` → `rewardRate = 0` | ❌ Fixed — `notifyRewardAmount` reverts with `RewardPeriodTooSmall` when the funded amount (reward + leftover) is below `REWARDS_DURATION`; a period can never silently fund zero rewards |
| 6 | **Principal canibalization** | Owner notifies an amount exceeding the reward surplus | ❌ Fixed — the notify cap uses `balanceOf(this) - totalStaked` (surplus over staked principal); staked principal can never be committed as rewards |
| 7 | **Rescue STK** | `recoverERC20(STK)` | ❌ Reverts — STK is always excluded (design D5) |
| 8 | **Access control** | Non-owner calls `notify`/`recover` | ❌ Reverts — `onlyOwner` |
| 9 | **Disproportionate stake** | 1 wei stake captures excess value | ❌ Blocked — global reward-per-token accumulator is fair |
| 10 | **Reward theft** | Attacker claims victim's rewards | ❌ Blocked — rewards isolated per user |

**Findings:** no exploitable vulnerability was found for an external attacker.
The two owner-side risks documented in the previous review (under-funded
notify that floored the rate to zero; the notify cap that included staked
principal) are also now closed by contract logic in commit `ad1203f` — both
required the *owner themselves* to act incorrectly and neither let a third
party steal funds.

### Security design principles

- **CEI ordering** on every mutative function (state before external calls).
- **ReentrancyGuard** on `stake`, `withdraw`, `claimRewards`, `exit`.
- **SafeERC20** for transfers; checked arithmetic (Solidity 0.8.36).
- **Internal accounting** — never trusts `balanceOf(this)` for liabilities
  (donation-safe).
- **`recoverERC20` excludes STK** — staked principal and reward pool are
  untouchable.
- **Lockup by design** — reverts `LockupNotEnded` until `lockupEndOf`.
- **Notify hardening** — `RewardPeriodTooSmall` revert below
  `REWARDS_DURATION`; reward cap excludes staked principal (`balance -
  totalStaked`).

---

## 5. Deployed on Sepolia — live and verified

### v2 (current) — hardened + timelock governance

The **v2** is the active contract: hardened code (`notifyRewardAmount` fix,
commit `ad1203f`) governed by a `TimelockController` — every owner action
(notify/recover) requires schedule → wait 2 days → execute. The owner can no
longer act instantly.

| Contract | Address (Sepolia) | Explorer |
|---|---|---|
| `StakingRewards` v2 | `0x1190ae86140b92118f9cb84061a8bfc19bbca781` | [etherscan](https://sepolia.etherscan.io/address/0x1190ae86140b92118f9cb84061a8bfc19bbca781) |
| `TimelockController` | `0x018efb5099505113625dabc5dc6f5513ad252c6b` | [etherscan](https://sepolia.etherscan.io/address/0x018efb5099505113625dabc5dc6f5513ad252c6b) |
| `StakingToken` (reused) | `0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5` | [etherscan](https://sepolia.etherscan.io/address/0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5) |

v2 deployment run (2026-08-04, `forge script script/DeployV2.s.sol --broadcast --verify`):

- **Deployer:** `0x6f81b75EDc0C7060aa5F1bA14B7fd45bD663A5bD`
- **Staking v2 deploy tx:** `0x43112aa4a41fff3ab9ba15ac22e6abdfc8be4892f42d8c1ff508c579535ff833`
- **Timelock deploy tx:** `0x0cfde46c9e58129d7677cc95b31bce5766f9abf9bc6f560819e5c9c78ba6b00b`
- **Pool funded + period 1 started + ownership handed to the timelock**
- **minDelay:** 172,800 s (2 days)

### v1 (legacy) — original deployed and verified

The **v1** was the first production version (pre-hardening code). It keeps
paying rewards until its `periodFinish`; the existing stake migrates when its
lockup expires (2026-09-03).

| Contract | Address (Sepolia) | Explorer |
|---|---|---|
| `StakingRewards` v1 | `0x42A3cFFDAE52Ed302Bb78D14071B386F85EFCfCc` | [etherscan](https://sepolia.etherscan.io/address/0x42A3cFFDAE52Ed302Bb78D14071B386F85EFCfCc) |
| `StakingToken` | `0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5` | [etherscan](https://sepolia.etherscan.io/address/0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5) |

Original deployment (2026-08-04, `forge script --broadcast --verify`):

- **Token deploy tx:** `0x78ecc3e6707138264f5d41a8a1feff8280e6652c90d242b075852e1be5f67f0d`
- **Staking deploy tx:** `0x553f1e444c6c307091258ca7812a33bf14592ea1ddacc7d803d7dfe6e0f7585f`

### Live on-chain state (v2)

- `totalSupply` 10,000,000 STK → 9,000,000 deployer / 1,000,000 reward pool
- `rewardRate` 128,600,823,045,267,488 ≈ 1e24 / 7,776,000 s
- `periodFinish` = v2 deploy + 90 days (2026-11-02)
- `owner` = TimelockController (2-day delay on every owner action)

### Real on-chain proof (v1)

The protocol was exercised with a **real transaction on Sepolia**:

- ✅ Staked 1,000 STK (tx `0xfd1b9b19f2578fbfe0f86e3a08cf254c47290bb6e44106ba7a383973078f53e3` — `Staked` event)
- ✅ Rewards accrued live (`earned()` grew per second)
- ✅ Claimed **467.59 STK** via the frontend dApp — verified on-chain (deployer balance +467.59 STK, pool −467.59 STK)

---

## 6. Frontend dApp

A landing-style React + Vite + TypeScript app in [`frontend/`](frontend/)
wired to the live Sepolia contracts with **wagmi + viem** (MetaMask injected
wallet). Hero + mission sections explain *why* the protocol exists; the app
panel provides wallet connect, protocol stats, your position (auto-refresh),
stake (approve + stake), claim rewards, withdraw and atomic exit — with
Etherscan links on every transaction and friendly error handling.

```shell
cd frontend
npm install
npm run dev        # http://localhost:5173
```

No private keys in the frontend — all signing happens in MetaMask.

---

## 7. Run it locally

```shell
# Contracts + tests (Foundry)
forge build
forge test                    # 58 tests
forge fmt --check

# Local chain
anvil &
PRIVATE_KEY=0xac09...f2ff80 \   # anvil account #0
  forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast

# v2 (hardened + timelock): reuse the token if present, or deploy a new one
TOKEN_ADDRESS=0x... \
PRIVATE_KEY=0xac09...f2ff80 \
  forge script script/DeployV2.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast

# dApp (frontend/)
cd frontend && npm install && npm run dev
```

---

## 8. Process artifacts

- **Spec-driven change record** — `openspec/changes/archive/2026-08-03-staking-protocol/`
  (proposal → specs → design → tasks → verify), showing the full
  requirements-to-verification trail.
- **Attack suite** — `test/SecurityAttack.t.sol` (10 adversarial PoCs).
- **Governance** — `test/Timelock.t.sol` (8 timelock integration tests).
- **Invariants** — `test/invariants/` (5 financial-truth rules).
- **Deploy record** — `broadcast/Deploy.s.sol/11155111/` (v1) and `broadcast/DeployV2.s.sol/11155111/` (v2).

## Out of scope (v1)

Vesting/penalties, mintable emissions, multi-token rewards, ERC-4626 shares,
permit, upgradeability, timelock, mainnet deploy, subgraph indexing.

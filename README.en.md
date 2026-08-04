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
  stake / withdraw / claimRewards / exit / exitEarly / notifyRewardAmount / recoverERC20
```

### Key mechanics

- **Stake** — deposit STK; your position locks for 30 days. Repeated stakes
  extend the whole position's lockup (design D3).
- **Earn** — rewards accrue every second via a reward-per-share accumulator
  while you are staked; claimable at any time, even during lockup. Only
  principal is locked.
- **Withdraw / Exit** — after `lockupEndOf`, withdraw principal; `exit()`
  atomically withdraws principal and claims rewards in one transaction.
- **Early exit** — during lockup, `exitEarly()` withdraws the full principal
  minus a **15% penalty** (`PENALTY_BPS`) that stays in the contract and
  strengthens the pool for stakers who wait. Accrued rewards stay claimable
  separately, without penalty (design D7).
- **Owner** — funds 90-day emission windows via `notifyRewardAmount()` and can
  rescue stuck external tokens via `recoverERC20()` (STK itself is excluded).

### Parameters

| Parameter | Value |
|---|---|
| `INITIAL_SUPPLY` | 10,000,000 STK |
| `REWARDS_DURATION` | 90 days (7,776,000 s) |
| `LOCKUP_DURATION` | 30 days (2,592,000 s) |
| Initial reward pool | 1,000,000 STK (10% of supply) |
| `PENALTY_BPS` | 1,500 (15% early-exit penalty) |
| Reward rate | `min(reward + leftover, balance - totalStaked) / REWARDS_DURATION` |

---

## 3. How it was tested — 67 tests, 6 layers

| Layer | Count | What it proves |
|---|---|---|
| Unit (token) | 8 | metadata, fixed supply, no mint, transfers/allowances + reverts |
| Unit (staking) | 27 | stake/lockup, linear accrual, claim, withdraw boundary, atomic exit, notify rate/cap/owner, recoverERC20 exclusions, reentrancy, lockup extension + fuzz-style round-trip and claim-idempotence cases |
| Early exit | 8 | exact 15% penalty, revert after lockup, revert with zero stake, rewards still claimable, other stakers intact, pool reinforcement, reentrancy PoC |
| Governance | 8 | owner = timelock, direct owner calls blocked, schedule/wait/execute flow, attacker cannot schedule/execute, recoverERC20 timelocked, hardened fix survives the timelock |
| Invariant | 5 | solvency, accounting conservation, monotonic principal, lockup integrity, rewards bounded |
| **Security attacks** | **11** | **adversarial PoCs trying to corrupt the protocol (see §4)** |

```shell
forge build                 # compile
forge test                  # full suite: 67 tests
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
attack vector. **All 11 attacks failed to corrupt the protocol** (9 blocked by
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
| 11 | **Exploited early exit** | Flash-stake + immediate `exitEarly()` in the same block | ❌ Blocked — early exit pays the 15% penalty to the pool; the attacker loses value instead of capturing it |

**Findings:** no exploitable vulnerability was found for an external attacker.
The two owner-side risks documented in the previous review (under-funded
notify that floored the rate to zero; the notify cap that included staked
principal) are also now closed by contract logic in commit `ad1203f` — both
required the *owner themselves* to act incorrectly and neither let a third
party steal funds.

### Security design principles

- **CEI ordering** on every mutative function (state before external calls).
- **ReentrancyGuard** on `stake`, `withdraw`, `claimRewards`, `exit`, `exitEarly`.
- **SafeERC20** for transfers; checked arithmetic (Solidity 0.8.36).
- **Internal accounting** — never trusts `balanceOf(this)` for liabilities
  (donation-safe).
- **`recoverERC20` excludes STK** — staked principal and reward pool are
  untouchable.
- **Lockup by design** — reverts `LockupNotEnded` until `lockupEndOf`.
- **Notify hardening** — `RewardPeriodTooSmall` revert below
  `REWARDS_DURATION`; reward cap excludes staked principal (`balance -
  totalStaked`).
- **Early exit with penalty** — `exitEarly()` during lockup keeps 15% in the
  pool; the net amount exits via `SafeERC20` and the penalty strengthens
  rewards for those who wait (design D7).

---

## 5. Deployed on Sepolia — live and verified

### v3 (current) — early exit + timelock governance

The **v3** is the active contract: adds `exitEarly()` (early exit with a 15%
penalty during lockup) on top of the hardened code (`notifyRewardAmount` fix,
commit `ad1203f`), governed by the same `TimelockController` — every owner
action (notify/recover) requires schedule → wait 2 days → execute. The owner
can no longer act instantly.

| Contract | Address (Sepolia) | Explorer |
|---|---|---|
| `StakingRewards` v3 | `0x5dd9d0B3189f0477392f0bA4B164823d5d030A65` | [etherscan](https://sepolia.etherscan.io/address/0x5dd9d0B3189f0477392f0bA4B164823d5d030A65) |
| `TimelockController` | `0x018efb5099505113625dabc5dc6f5513ad252c6b` | [etherscan](https://sepolia.etherscan.io/address/0x018efb5099505113625dabc5dc6f5513ad252c6b) |
| `StakingToken` (reused) | `0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5` | [etherscan](https://sepolia.etherscan.io/address/0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5) |

v3 deployment run (2026-08-04, `forge script script/DeployV3.s.sol --broadcast --verify`):

- **Deployer:** `0x6f81b75EDc0C7060aa5F1bA14B7fd45bD663A5bD`
- **Staking v3 deploy tx:** see broadcast/DeployV3.s.sol/11155111/run-latest.json
- **Timelock + Token reused** from v2 (not redeployed)
- **Pool funded + period 1 started + ownership handed to the timelock**
- **minDelay:** 172,800 s (2 days) · **PENALTY_BPS:** 1,500 (15%)

### v2 (legacy) — hardened + timelock governance

The **v2** was the first hardened version (`notifyRewardAmount` fix, commit
`ad1203f`) with timelock governance. It was replaced by v3 (early exit); it
keeps paying rewards until its `periodFinish` and no new stake uses this
contract.

| Contract | Address (Sepolia) | Explorer |
|---|---|---|
| `StakingRewards` v2 | `0x1190ae86140b92118f9cb84061a8bfc19bbca781` | [etherscan](https://sepolia.etherscan.io/address/0x1190ae86140b92118f9cb84061a8bfc19bbca781) |
| `TimelockController` | `0x018efb5099505113625dabc5dc6f5513ad252c6b` | [etherscan](https://sepolia.etherscan.io/address/0x018efb5099505113625dabc5dc6f5513ad252c6b) |
| `StakingToken` (reused) | `0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5` | [etherscan](https://sepolia.etherscan.io/address/0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5) |

### Live on-chain state (v3)

- `totalSupply` 10,000,000 STK → ~9,000,000 deployer / 1,000,000 reward pool
- `rewardRate` 128,600,823,045,267,488 ≈ 1e24 / 7,776,000 s
- `periodFinish` = v3 deploy + 90 days (2026-11-02)
- `owner` = TimelockController (2-day delay on every owner action)
- `PENALTY_BPS` = 1,500 (15%)

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
stake (approve + stake), claim rewards, withdraw, atomic exit and early exit
with penalty — with Etherscan links on every transaction and friendly error
handling.

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
forge test                    # 67 tests
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

# v3 (early exit): reuse the token and the timelock
TOKEN_ADDRESS=0x... TIMELOCK_ADDRESS=0x... \
PRIVATE_KEY=0xac09...f2ff80 \
  forge script script/DeployV3.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast

# dApp (frontend/)
cd frontend && npm install && npm run dev
```

---

## 8. Process artifacts

- **Spec-driven change record** — `openspec/changes/archive/2026-08-03-staking-protocol/`
  (proposal → specs → design → tasks → verify), showing the full
  requirements-to-verification trail.
- **Attack suite** — `test/SecurityAttack.t.sol` (11 adversarial PoCs).
- **Governance** — `test/Timelock.t.sol` (8 timelock integration tests).
- **Early exit** — `test/EarlyExit.t.sol` (8 penalty and security tests).
- **Invariants** — `test/invariants/` (5 financial-truth rules).
- **Deploy record** — `broadcast/Deploy.s.sol/11155111/` (v1), `broadcast/DeployV2.s.sol/11155111/` (v2) and `broadcast/DeployV3.s.sol/11155111/` (v3).

## Out of scope (v1)

Vesting/penalties, mintable emissions, multi-token rewards, ERC-4626 shares,
permit, upgradeability, mainnet deploy, subgraph indexing.

> Note: "Out of scope (v1)" is kept as a historical record — the early-exit
> penalty is already implemented in v3.

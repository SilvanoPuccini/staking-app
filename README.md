# Staking Protocol v1

A minimal, audited-by-invariants staking dApp: **StakingToken (STK)** — a fixed-supply
ERC-20 — plus **StakingRewards**, a Synthetix-style staking contract with a 30-day
principal lockup and time-based rewards paid in STK from a pre-funded pool.

Built with Foundry, following the Blockchain Accelerator curriculum:
**block 3** (ERC-20), **block 7** (staking app), **block 6** (Foundry testing),
**block 13** (smart-contract security).

**Live on Ethereum Sepolia testnet** — contracts deployed and verified on
Etherscan; see [Deployed on Sepolia](#deployed-on-sepolia).

## Quick path

```shell
forge build          # compile (solc 0.8.36, optimizer 200)
forge test           # 40 tests: 8 token unit + 27 staking (24 unit + 3 fuzz) + 5 invariants
forge fmt --check    # formatting gate

# Local deploy on anvil (task 3.4):
anvil &                               # local node, deterministic accounts
PRIVATE_KEY=0xac09...f2ff80 \          # anvil account #0
  forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 --broadcast
```

After the local deploy the contracts live at the deterministic addresses below
(FOUNDRY CREATE nonces on a fresh anvil chain).

| Contract | Address (anvil, fresh chain) |
|---|---|
| `StakingToken` | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| `StakingRewards` | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |

> These addresses only hold on a brand-new anvil instance (chain id 31337).
> Reset anvil or redeploy and re-read the script logs for your run.

## Deployed on Sepolia

Live deployment (chain id 11155111) with both contracts verified on Etherscan:

| Contract | Address (Sepolia) | Explorer |
|---|---|---|
| `StakingToken` | `0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5` | [etherscan](https://sepolia.etherscan.io/address/0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5) |
| `StakingRewards` | `0x42A3cFFDAE52Ed302Bb78D14071B386F85EFCfCc` | [etherscan](https://sepolia.etherscan.io/address/0x42A3cFFDAE52Ed302Bb78D14071B386F85EFCfCc) |

Deployment run (2026-08-04, `forge script --broadcast --verify`):

- **Deployer:** `0x6f81b75EDc0C7060aa5F1bA14B7fd45bD663A5bD`
- **Token deploy tx:** `0x78ecc3e6707138264f5d41a8a1feff8280e6652c90d242b075852e1be5f67f0d`
- **Staking deploy tx:** `0x553f1e444c6c307091258ca7812a33bf14592ea1ddacc7d803d7dfe6e0f7585f`
- **Reward pool funded + first 90-day period started** (`notifyRewardAmount(1e24)`)

On-chain state at deploy:

- `totalSupply` 10,000,000 STK → 9,000,000 deployer / 1,000,000 reward pool
- `rewardRate` 128,600,823,045,267,489 ≈ 1e24 / 7,776,000 s
- `periodFinish` = deploy + 90 days; `totalStaked` 0 (no stakers yet)

Interact (read): `cast call 0x42A3... "rewardRate()(uint256)" --rpc-url sepolia`
Interact (write, owner): `cast send 0x42A3... "stake(uint256)" <amount> --rpc-url sepolia --private-key $PRIVATE_KEY`

## What the protocol does

- **Stake** STK with an approved allowance; your position is locked for 30 days
  (`lockupEndOf(you) = stake timestamp + 30d`). **Repeated stakes extend the
  whole position's lockup** to the newest stake + 30d (design D3).
- **Earn** per-second rewards from a pre-funded pool while staked — claimable at
  any time via `claimRewards()`, even during lockup. Only principal is locked.
- **Withdraw** principal once past `lockupEndOf`; **`exit()`** atomically
  withdraws principal and claims rewards in one call.
- **Owner** funds reward periods with `notifyRewardAmount(amount)`, which starts
  a fresh 90-day emission window, and rescues stuck external tokens with
  `recoverERC20`.

### Parameters

| Parameter | Value | Notes |
|---|---|---|
| `StakingToken.INITIAL_SUPPLY` | 10,000,000 STK (10M × 1e18) | minted once to deployer; no mint/burn |
| `StakingRewards.REWARDS_DURATION` | 7,776,000 s (90 days) | emission window per `notifyRewardAmount` |
| `StakingRewards.LOCKUP_DURATION` | 2,592,000 s (30 days) | principal lockup per stake |
| Reward rate | `min(reward + leftover, balance) / REWARDS_DURATION` | per-second, 1e18 fixed point |
| Initial deploy funding | 1,000,000 STK pool | 10% of supply; see `script/Deploy.s.sol` |

## Architecture

```
StakingToken (ERC-20, fixed supply)
        │ transfers / approvals
        ▼
StakingRewards (Ownable, ReentrancyGuard, SafeERC20)
  stake / withdraw / claimRewards / exit / notifyRewardAmount / recoverERC20
  state: periodFinish, rewardRate, totalStaked, balances, lockupEndOf,
         rewardPerTokenStored, _rewards, _userRewardPerTokenPaid
```

Rewards use a Synthetix reward-per-share accumulator (one checkpointed global
scalar + per-user checkpoints — no per-user loops, no balance-based accounting).
Rewards accrue per second while `totalStaked > 0`; with zero stakers the
accumulator freezes and empty time pays nothing (design D2).

### Invariants (test/invariants/)

The invariant suite drives the contract through 256 random sequences × 128 calls
(handler-based, bounded amounts, random 0–45d time jumps) and asserts
financial-truth rules after every sequence:

1. **Solvency** — `STK balance ≥ totalStaked + committed-but-unpaid rewards`
2. **Accounting conservation** — `Σ balances == totalStaked`
3. **Monotonic principal** — a user's balance never exceeds their deposits
4. **Lockup integrity** — `lockupEndOf == last stake + 30d`
5. **Rewards bounded** — cumulative payouts ≤ funds pushed into the pool

Run them with `forge test` (default) or
`FOUNDRY_INVARIANT_RUNS=256 FOUNDRY_INVARIANT_DEPTH=128 forge test`.

## Security considerations

- **CEI ordering** on every mutative function: state and checkpoints update
  before any external transfer.
- **ReentrancyGuard** on `stake`, `withdraw`, `claimRewards`, `exit`.
- **SafeERC20** for all token transfers; **checked arithmetic** (Solidity 0.8.36).
- **Ownable**: `notifyRewardAmount` and `recoverERC20` are owner-only.
- **Internal accounting** — the protocol tracks balances/totals itself and never
  trusts `balanceOf(this)` for liabilities (donation-safe).
- **`recoverERC20` excludes STK entirely** (design D5): STK in the contract backs
  staked principal and the reward pool, so it can never be rescued — accidental
  STK donations fund future rewards instead.
- **Lockup is by design**: withdrawing before `lockupEndOf` reverts with
  `LockupNotEnded`; rewards remain claimable meanwhile.

### Known caveat: notify with under-funding

`notifyRewardAmount` caps the period at the contract's STK balance. If the funded
amount is **smaller than `REWARDS_DURATION`** (7,776,000 base units), the integer
division floors `rewardRate` to **0** — the 90-day period silently funds nothing.
The owner must top up and **re-notify**. The protocol is safe (nothing is
over-committed); only the emission is lost. This is exactly the floor the
invariant ghost tracks (see `test/invariants/Handler.sol` `notify`).

## Testing

| Layer | Count | What it proves |
|---|---|---|
| Unit (token) | 8 | metadata, fixed supply, no mint, transfers/allowances + reverts |
| Unit (staking) | 24 | stake/lockup, linear accrual, claim (incl. in-lockup, no double), withdraw boundary, atomic exit, notify rate/cap/owner, recoverERC20 exclusions, reentrancy, D3 lockup extension, defensive reverts |
| Fuzz | 3 | round-trip, accrued ≤ funded pool, claim idempotence (@2000 runs verified) |
| Invariant | 5 | solvency, accounting conservation, monotonic principal, lockup, rewards-bounded |

```shell
forge test                 # full suite
forge test --match-contract StakingRewardsInvariants   # invariants only
forge coverage             # ~99% lines on src/
```

## Rollback / reset

Greenfield: reset the anvil chain (`pkill anvil`) and redeploy — no migrations,
no upgrade path (out of scope). The change record lives under
`openspec/changes/archive/2026-08-03-staking-protocol/` (proposal → specs →
design → tasks → verify). The Sepolia deployment is a one-shot v1; contract
upgrades are out of scope.

## Out of scope (v1)

Frontend dApp, vesting/penalties, mintable emissions, multi-token rewards,
ERC-4626 shares, permit, upgradeability, timelock, mainnet deploy.

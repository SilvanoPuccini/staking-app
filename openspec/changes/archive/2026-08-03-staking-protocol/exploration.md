# Exploration: Staking App — StakingToken (ERC-20) + StakingRewards

> Synthesized from Engram `sdd/staking-app/explore` (obs #1012). Product decisions made after exploration are marked **[DECIDED]** — they are authoritative and supersede this document where they differ.

## Current State

- `/home/silvano/dev/staking-app` is a fresh git repo: no commits, no code. OpenSpec skeleton only (`openspec/config.yaml`, empty `specs/`, empty `changes/`).
- Toolchain ready: Foundry 1.5.1 (`forge`/`cast`/`anvil`), solc 0.8.36, Node 22.
- Curriculum coverage: blocks 3 (ERC-20), 7 (Staking), 6 (Foundry testing), 13 (security).
- Preflight: pace=interactive, artifact_store=both, chained_pr_strategy=force-chained, review_budget_lines=800.

## Affected Areas (future files — nothing exists yet)

- `src/StakingToken.sol` — ERC-20 token, block 3.
- `src/StakingRewards.sol` — staking contract, block 7.
- `test/StakingRewards.t.sol` (+ fuzz/invariant), block 6.
- `script/Deploy.s.sol` — forge deploy script.
- `openspec/changes/staking-protocol/` — proposal, specs, design, tasks, verify.

## Design Decisions

1. **ERC-20 StakingToken** **[DECIDED: name "StakingApp Token", symbol STK; supply 10,000,000 * 1e18 minted once to deployer; 18 decimals]**: OpenZeppelin `ERC20` (never hand-roll). Fixed initial supply, NOT mintable in v1 — keeps supply accounting trivial and rewards honest. Deferred: mintable w/ minter role, permit (EIP-2612), burnable, snapshots.

2. **Reward token: SAME token (STK)**. Single-token system = one contract, one trust assumption. Rewards funded by admin transferring STK into StakingRewards (Synthetix `notifyRewardAmount` model), NOT minted. Caps payout to funded balance (no insolvency), simplifies invariants.

3. **Staking contract surface** **[DECIDED: name StakingRewards; 30-day minimum lockup ADDED vs. exploration]**: `stake(uint)`, `withdraw(uint)`, `claimRewards()`, `exit()`; views: `earned(user)`, `rewardPerToken()`, `balanceOf`, `totalStaked`, `lockupEndOf(user)`. Withdraw blocked until `lockupEnd` (depositTimestamp + 30d); rewards still accrue during lockup. **[DECIDED overrides exploration's "no lockup in v1".]**

4. **Rewards model** **[DECIDED: rewardsDuration = 90 days]**: time-based accumulator (Synthetix StakingRewards simplified), not block-based, not naive per-user APY:
   - `rewardPerTokenStored += (now - lastUpdateTime) * rewardRate * 1e18 / totalStaked` (guard `totalStaked == 0`)
   - `earned(u) = (rewardPerTokenStored - u.rewardPerTokenPaid) * u.staked / 1e18`
   - `rewardRate = amount / rewardsDuration`, set by `notifyRewardAmount` (owner, capped at contract balance)
   - Checkpoint before any stake/withdraw; CEI ordering everywhere.

## Approaches Compared

1. **Time-based reward-per-share (Synthetix StakingRewards) — RECOMMENDED**: canonical audited pattern; time-based = intuitive APY; chain-agnostic; tests via `vm.warp`; funded pool = honest, bounded payout; simple invariant (`balance >= totalStaked + paid`). Cons: fixed per-period rewards; needs admin top-ups. Effort: Low-Medium (~150-200 LOC + OZ deps).
2. **Block-based per-share (MasterChef simplified)**: canonical yield-farming pattern (block 15), but chain-dependent APR and typically needs minter role. Effort: Medium.
3. **Naive per-user APY accumulator — ANTI-PATTERN**: reward liability grows with TVL while funding is fixed → insolvency. Not real.

## Recommendation

Approach 1: OZ ERC20 fixed-supply StakingToken + StakingRewards (time-based accumulator, same-token rewards, pre-funded pool, 30d lockup) + Foundry suite (unit + fuzz + invariant) + forge deploy script. Covers blocks 3/7/6/13. Completable in one change.

## Security (block 13)

- CEI ordering on all mutative functions; OZ `ReentrancyGuard`.
- Solidity 0.8.x checked math; 1e18-scaled accumulator.
- SafeERC20 for all token ops; zero-`totalStaked` guard (division).
- `notifyRewardAmount` capped at contract balance; `recoverERC20` owner-only, excludes staked + undistributed reward principal.
- Ownable (OZ v5) for admin fns; optional Pausable (emergency). No proxy/timelock/roles in v1.
- Invariant tests: supply conservation; `balance >= totalStaked + cumulativeRewardsPaid`; no double-claim; fuzz amounts/time.

## Scope Boundaries (v1 include / defer)

- **INCLUDE**: token, staking contract, tests (unit+fuzz+invariant), deploy script, security pass, README.
- **DEFER** **[all DECIDED]**: frontend dApp (block 21 bonus), vesting/penalties, mintable emissions, multi-token rewards, ERC-4626 shares, permit, upgradeability, timelock, testnet deploy+verify. **[DECIDED: deploy target v1 = local anvil only.]**

## Risks / Open Questions

- **[RESOLVED by user]** Tokenomics: STK, 10M supply, 90d duration, pre-funded pool, 30d lockup, anvil-only.
- **Still open**: initial funding amount for the reward pool; lockup interaction with `exit()`; `recoverERC20` exclusion semantics.
- 800-line review budget: contracts+tests likely exceed → force-chained PRs (cached); forecast in sdd-tasks.
- `config.yaml` still reflects empty-repo state (Foundry "not installed", `tdd:false`) — stale vs actual; refresh during init/apply follow-up.

## Ready for Proposal

Exploration complete; next phase was sdd-propose, which named the change `staking-protocol` and produced this folder. This exploration.md fulfills the explore phase's deferred deliverable.

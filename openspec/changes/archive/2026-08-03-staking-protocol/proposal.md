# Proposal: Staking Protocol v1

## Intent

Greenfield portfolio project (Accelerator blocks 3/7/6/13): honest staking protocol — own ERC-20 token + time-based staking contract — Foundry-tested, security-reviewed, anvil-deployed. Repo is empty; this change creates v1 in full.

## Scope

### In Scope
- StakingToken: OZ ERC-20 "StakingApp Token" (STK), 10,000,000 * 1e18 minted once to deployer, 18 decimals, no further minting.
- StakingRewards: stake/withdraw/claimRewards/exit; time-based reward-per-share accumulator; same-token rewards; pre-funded pool.
- 30-day minimum lockup (stake timestamp + 30d); rewards accrue during lockup.
- Foundry suite (unit + fuzz + invariant) + deploy script + README + security pass.

### Out of Scope
Frontend dApp (block 21 bonus), vesting/penalties, mintable emissions, multi-token rewards, ERC-4626 shares, permit, upgradeability, timelock, testnet deploy+verify.

## Capabilities

### New Capabilities
- `staking-token`: ERC-20 STK, fixed supply, OZ standard (block 3).
- `staking-rewards`: deposit/withdraw/claim/exit, time-based accumulator, 30d lockup, pre-funded rewards (blocks 7/13).

### Modified Capabilities
None.

## Business Rules
- STK supply fixed at 10M * 1e18, minted once; no further minting.
- rewardsDuration = 90 days (constant seconds).
- notifyRewardAmount(amount): admin-only, capped by contract balance; rewardRate = amount / rewardsDuration.
- Withdraw reverts before lockupEnd (stake + 30d); rewards still accrue.
- earned(u) = (rewardPerToken − u.rewardPerTokenPaid) × u.staked / 1e18; checkpoint before stake/withdraw.

## Approach

Two minimal contracts. StakingToken: OZ ERC20, constructor mint. StakingRewards: reward-per-share accumulator — stake() stores balance + lockupEnd; withdraw() enforces lockup; claimRewards() pays earned; exit() = withdraw + claim. SafeERC20; Ownable; ReentrancyGuard; optional Pausable. Tests: unit (happy path, lockup revert), fuzz (amounts/time), invariants (supply conservation; balance >= totalStaked + rewardsPaid; no double-claim).

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| src/StakingToken.sol, src/StakingRewards.sol | New | ERC-20 + staking/lockup |
| test/, test/invariants/ | New | Forge unit/fuzz/invariant |
| script/Deploy.s.sol | New | Anvil deploy |
| foundry.toml, .gitignore, README.md | New | Scaffold |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Lockup traps users (by design) | Med | lockupEnd view, clear revert, docs |
| notifyRewardAmount overfunds | Low | Cap at balance; bounded duration |
| Pool exhaustion mid-period | Med | Accrual stops; admin top-up |
| Zero totalStaked division | Low | Guard before update |
| Donation/balance-based accounting | Med | Internal accounting, not balanceOf |
| 800-line review budget | High | Force-chained PRs (cached) |

## Rollback Plan

Greenfield repo, anvil-only: delete `openspec/changes/staking-protocol/` or reset branch. Deployed contracts live on ephemeral anvil — redeploy fresh.

## Dependencies

- OpenZeppelin Contracts v5.x (forge install); Foundry 1.5.1; solc 0.8.36.

## Success Criteria

- [ ] forge build + forge test green (unit + fuzz + invariant)
- [ ] Withdraw before lockupEnd reverts; after passes
- [ ] Invariants hold: supply conserved; balance >= totalStaked + rewardsPaid
- [ ] Deploy script runs on anvil; owner funds; stakers earn via vm.warp
- [ ] Security pass documented; covers blocks 3/7/6/13

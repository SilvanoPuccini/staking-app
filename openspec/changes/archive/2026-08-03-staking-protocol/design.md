# Design: Staking Protocol v1

## Technical Approach
Two minimal contracts: `StakingToken` (OZ ERC20, fixed supply) + `StakingRewards` (Synthetix-style reward-per-share accumulator, same-token rewards, 30-day lockup, pre-funded pool). Foundry unit/fuzz/invariant + anvil deploy. Fulfills proposal + both specs; defers frontend, vesting, mintable, ERC-4626, permit, upgradeability, testnet.

## Architecture Decisions

| # | Decision | Choice | Alternatives | Rationale |
|---|---|---|---|---|
| D1 | notifyRewardAmount top-up | Synthetix carryover: `leftover = (periodFinish−now)·rewardRate` if now < periodFinish; `rewardRate = min(reward+leftover, balanceOf(this)) / 7_776_000` | revert-if-too-high (spec mandates cap); drop leftover | `updateReward(0)` runs first → leftover is the undistributed remainder; cap keeps liability ≤ balance |
| D2 | Accrual at totalStaked==0 | Synthetix pause: `rewardPerToken()` returns stored value (no division); checkpoints advance `lastUpdateTime`, skipping empty time; first stake snapshots at frozen value, accrual resumes | extend `periodFinish` by empty time; virtual accrual (div-by-zero) | rewards only stakers; empty time unpaid (spec: no update while zero) |
| D3 | Lockup state model | Single per-user `_balances` + `_lockupEndOf`; each `stake()` sets `lockupEndOf = now + 30d` | per-deposit arrays (FIFO, partial-withdraw splitting, gas) | spec scenarios use one `lockupEndOf`; math needs only total + per-user balance. Documented: repeated stakes extend the whole position's lockup |
| D4 | exit() semantics | Atomic: checkpoint → lockup check (reverts before lockupEnd) → transfer principal + earned → zero balances | sequential `claimRewards()`+`withdraw()` — not atomic | spec requires atomic revert during lockup; claim via `claimRewards()` meanwhile |
| D5 | recoverERC20 | Reverts for STK always; rescues external tokens only | STK up to `balance − liabilities` (unbounded user iteration) | spec requires principal/reward-pool revert; total block strictly safer; STK donations fund future rewards |
| D6 | Dependencies | OZ Contracts pinned v5.x at `forge install`; solc 0.8.36; `Ownable(initialOwner)` ctor arg | — | matches proposal; OZ v5 ReentrancyGuard/SafeERC20/Ownable |

## State Model (StakingRewards)
`periodFinish`, `rewardRate`, `lastUpdateTime`, `rewardPerTokenStored`, `totalStaked`; mappings `_balances`, `_lockupEndOf`, `_rewards`, `userRewardPerTokenPaid`; immutable `stakingToken` (== reward token).

## Key Formulas
```
rewardPerToken = stored + (totalStaked==0 ? 0 : (min(now,periodFinish) - lastUpdateTime) * rewardRate * 1e18 / totalStaked)
earned(u) = _balances[u] * (rewardPerToken - userRewardPerTokenPaid[u]) / 1e18 + _rewards[u]
notify: leftover = now < periodFinish ? (periodFinish - now) * rewardRate : 0
        rewardRate = min(reward + leftover, balanceOf(this)) / 7_776_000   // 90 days
lockupEndOf[u] = block.timestamp + 2_592_000                               // 30 days
```
Overflow bound: `rewardRate ≤ balance/7_776_000` → max intermediate ≈ 1e43 ≪ 2^256; 0.8 checked math suffices.

## Data Flow
```
stake(amt):    updateReward → lockupEnd=now+30d → totalStaked+=amt → safeTransferFrom
claimRewards(): updateReward → reward=_rewards[user] → safeTransfer → _rewards=0      (anytime)
withdraw(amt): updateReward → require now≥lockupEndOf → safeTransfer principal → deduct
exit():        updateReward → lockup check → safeTransfer principal+earned → zero balances (atomic)
notify(1M):    updateReward(0) → top-up → cap → periodFinish=now+90d
```

## File Changes
| File | Action | Description |
|---|---|---|
| `foundry.toml`, `.gitignore`, `README.md` | Create | Scaffold (solc 0.8.36, libs `lib/`) |
| `src/StakingToken.sol` | Create | OZ ERC20 "StakingApp Token"/STK, mint 10M·1e18 to deployer, no mint/burn |
| `src/StakingRewards.sol` | Create | Accumulator + lockup + stake/withdraw/claim/exit + admin |
| `test/StakingToken.t.sol` | Create | Token metadata/supply/transfer specs |
| `test/StakingRewards.t.sol` | Create | Unit + fuzz (lockup, claims, notify, recover) |
| `test/invariants/Handler.sol` + `StakingRewardsInvariants.t.sol` | Create | Stateful invariant suite |
| `script/Deploy.s.sol` | Create | Anvil: token → approve → SR → fund 1M STK → notify |

## Interfaces
```solidity
interface IStakingRewards {
    function stake(uint256) external;
    function withdraw(uint256) external;              // reverts before lockupEnd
    function claimRewards() external;
    function exit() external;
    function notifyRewardAmount(uint256) external;    // onlyOwner
    function recoverERC20(address, uint256) external; // onlyOwner; STK reverts
    function rewardPerToken() external view returns (uint256);
    function earned(address) external view returns (uint256);
    function lockupEndOf(address) external view returns (uint256);
}
```
Security: CEI ordering; `ReentrancyGuard`; `SafeERC20`; Ownable; zero-totalStaked guard; internal accounting (never balanceOf-based); 1e18 fixed point; checked arithmetic.

## Testing Strategy
| Layer | What | Approach |
|---|---|---|
| Unit | Token: metadata/supply/transfer-revert. SR: stake+lockupEnd; stake(0) revert; withdraw blocked/boundary; claim in lockup; no double-claim; exit atomic + lockup revert; notify rate/cap/owner-only; recover external ok / STK revert; reentrancy via hooky mock | forge + vm.prank/warp/expectRevert |
| Fuzz | Amounts & timestamps: earned monotonic, no false reverts, math bounds | forge fuzz + vm.assume |
| Invariant | (a) balance ≥ totalStaked + committed-but-unpaid rewards; (b) balance ≥ totalStaked; (c) rewardsPaid ≤ fundedGhost; totalStaked == Σ _balances; claims ≤ earned; withdraw only past lockupEnd | handler-driven + random warp |

## Threat Matrix
N/A — pure on-chain Solidity design; no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration boundary in this artifact.

## Migration / Rollout
None — greenfield, anvil-only; redeploy on reset. No migrations or feature flags.

## Open Questions
- [x] Pin exact OZ tag at install (v5.2.0 — `acd4ff74`, recorded in `lib/`; verified in PR 1).
- [x] Confirm repeated-stake lockup extension (D3) is acceptable v1 UX — confirmed; documented in README and covered by `testSecondStakeExtendsLockupEnd` (PR 3).
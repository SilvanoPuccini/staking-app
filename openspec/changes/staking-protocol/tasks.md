# Tasks: Staking Protocol v1

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~950 total (A ~145, B ~450, C ~350) |
| 400-line budget risk | Medium (slice B ~450 exceeds default) |
| 800-line budget risk | Low (every slice under cached 800) |
| Chained PRs recommended | Yes (force-chained cached) |
| Suggested split | PR 1 → PR 2 → PR 3 (stacked to main) |
| Delivery strategy | ask-on-risk |
| Chain strategy | stacked-to-main (cached) |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium
800-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Scaffold + StakingToken + token tests | PR 1 | `forge test --match-contract StakingTokenTest` | N/A — pure unit, no chain integration in slice | `git rm` foundry.toml, .gitignore, src/StakingToken.sol, test/StakingToken.t.sol, lib/ |
| 2 | StakingRewards + unit & fuzz tests | PR 2 | `forge test --match-contract StakingRewardsTest` | N/A — forge VM only; anvil deferred to PR 3 | remove src/StakingRewards.sol + test/StakingRewards.t.sol |
| 3 | Invariants + Deploy script + README | PR 3 | `forge test --match-contract StakingRewardsInvariants` | `anvil` + `forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast`; cast stake → warp → claim spot checks | remove test/invariants/, script/Deploy.s.sol, README.md |

## Phase 1: Foundation & Token (PR 1)

- [x] 1.1 `forge init --force`; foundry.toml: solc 0.8.36, libs `lib/`, optimizer 200
- [x] 1.2 `forge install OpenZeppelin/openzeppelin-contracts`; pin v5.x tag, record tag in lib/
- [x] 1.3 Create `.gitignore` (out/, cache/, broadcast/, .env)
- [x] 1.4 RED: test/StakingToken.t.sol — metadata ("StakingApp Token"/STK/18), supply==balanceOf(deployer)==10M·1e18, no mint fn, transfer + Transfer event, transfer>balance reverts
- [x] 1.5 GREEN: src/StakingToken.sol — OZ ERC20, ctor mint 10M·1e18 to deployer, no mint/burn; make 1.4 green

## Phase 2: StakingRewards — Unit & Fuzz (PR 2)

- [x] 2.1 RED: test/StakingRewards.t.sol — first deposit (totalStaked+1000, lockupEnd==ts+30d); stake(0) reverts
- [x] 2.2 RED: linear accrual (earned==1d of rate after vm.warp); zero-totalStaked returns stored value, no div-0
- [x] 2.3 RED: claim inside lockup transfers earned and zeroes it; no double claim
- [x] 2.4 RED: withdraw blocked in lockup reverts; at lockupEnd boundary full principal transfers, totalStaked decreases
- [x] 2.5 RED: exit atomic after lockup (principal+rewards same call); notify: rate==1M·1e18/7_776_000, capped-by-balance, owner-only revert
- [x] 2.6 RED: recoverERC20 external token ok / STK reverts; reentrancy via malicious token hook reverts
- [x] 2.7 GREEN: src/StakingRewards.sol — accumulator, 30d lockup, stake/withdraw/claim/exit, notify carryover+cap, recoverERC20, Ownable+ReentrancyGuard+SafeERC20+CEI; 2.1–2.6 green
- [x] 2.8 RED+GREEN: fuzz — vm.assume amounts/timestamps: earned monotonic via warp, no false reverts, overflow bound asserted

## Phase 3: Invariants & Deploy (PR 3)

- [ ] 3.1 RED: test/invariants/Handler.sol — stake/withdraw/claim/notify actions + random warp; ghost totalStaked/rewardsPaid
- [ ] 3.2 RED: test/invariants/StakingRewardsInvariants.t.sol — balance ≥ totalStaked+ΣrewardsPaid; totalStaked==Σbalances; claims≤earned; withdraw only past lockupEnd; targetContract(Handler)
- [ ] 3.3 GREEN: fix contract/handler until invariants hold; `forge test -vv` green
- [ ] 3.4 script/Deploy.s.sol — anvil: deploy token → approve → deploy SR → fund 1M STK → notify 1M; broadcast + cast spot checks

## Phase 4: Docs & Polish (PR 3)

- [ ] 4.1 README.md — overview, architecture, security notes (lockup by design; recover STK reverts), anvil deploy/verify commands
- [ ] 4.2 `forge fmt`; full `forge test` green; resolve open questions (pin OZ tag; document repeated-stake lockup extension D3)

# StakingRewards Specification

## Purpose

StakingRewards accepts STK deposits under a 30-day minimum lockup and pays time-based rewards in the same token from a pre-funded pool. Rewards accrue continuously and are claimable even during lockup; only principal withdrawal is deferred until lockupEnd.

## Requirements

### Requirement: Stake With Lockup

stake(amount) MUST transfer amount STK via approved allowance, record the staker's balance, set lockupEndOf(staker) to block.timestamp + 30 days, and checkpoint rewards before updating state.

#### Scenario: First deposit

- GIVEN a staker with 1,000 STK and an approved allowance
- WHEN stake(1,000 STK) is called
- THEN totalStaked MUST increase by 1,000
- AND lockupEndOf(staker) MUST equal deposit timestamp + 30 days

#### Scenario: Zero amount reverts

- GIVEN any account
- WHEN stake(0) is called
- THEN the call MUST revert

### Requirement: Time-Based Reward Accrual

Rewards MUST accrue per second: rewardPerToken MUST increase by (block.timestamp - lastUpdateTime) * rewardRate * 1e18 / totalStaked, and MUST NOT update while totalStaked is zero. earned(user) MUST equal (rewardPerToken - rewardPerTokenPaid[user]) * staked[user] / 1e18.

#### Scenario: Rewards accrue linearly

- GIVEN 1,000 STK staked and an active funded period
- WHEN one day elapses
- THEN earned(staker) MUST equal one day of rewardRate accrual

#### Scenario: Zero totalStaked guard

- GIVEN a funded pool with no deposits
- WHEN rewardPerToken() is queried
- THEN it MUST NOT divide by zero and MUST return the stored value

### Requirement: Claim During Lockup

claimRewards() MUST transfer the full earned amount to the caller at any time, including before lockupEnd, and MUST reset rewardPerTokenPaid[user].

#### Scenario: Claim inside lockup

- GIVEN a staker with accrued rewards but lockupEnd in the future
- WHEN claimRewards() is called
- THEN the earned amount MUST be transferred
- AND earned(staker) MUST become zero

#### Scenario: No double claim

- GIVEN a staker whose rewardPerTokenPaid equals rewardPerToken
- WHEN claimRewards() is called
- THEN no more than the unclaimed amount MUST be transferred

### Requirement: Withdraw After Lockup

withdraw(amount) MUST revert while block.timestamp < lockupEndOf(caller), and after lockupEnd MUST transfer the requested principal and checkpoint rewards first.

#### Scenario: Withdraw blocked during lockup

- GIVEN a staker inside the 30-day window
- WHEN withdraw(any positive amount) is called
- THEN the call MUST revert

#### Scenario: Withdraw at the boundary

- GIVEN a staker whose lockupEnd equals the current timestamp
- WHEN withdraw(full principal) is called
- THEN the full principal MUST transfer
- AND totalStaked MUST decrease by that amount

### Requirement: exit

exit() MUST atomically claim rewards and withdraw the full principal. Because withdrawal is subject to lockup, exit() MUST revert before lockupEnd; users claim via claimRewards() meanwhile.

#### Scenario: Exit after lockup

- GIVEN a staker past lockupEnd with accrued rewards
- WHEN exit() is called
- THEN principal MUST be withdrawn AND rewards MUST be claimed in the same call

### Requirement: notifyRewardAmount

notifyRewardAmount(amount) MUST be owner-only, MUST cap the funded amount at the contract's STK balance, MUST add any undistributed remainder of the current period, and MUST set rewardRate = funded / rewardsDuration, where rewardsDuration is 7,776,000 seconds (90 days), restarting the period at the current timestamp.

#### Scenario: Initial funding

- GIVEN the owner transferred 1,000,000 STK to the contract
- WHEN notifyRewardAmount(1,000,000 STK) is called
- THEN rewardRate MUST equal 1,000,000 * 1e18 / 7,776,000
- AND rewards MUST start accruing from the current timestamp

#### Scenario: Capped by balance

- GIVEN a contract STK balance of 500 STK
- WHEN notifyRewardAmount(1,000 STK) is called
- THEN the funded amount MUST be capped at 500
- AND rewardRate MUST derive from the capped amount

#### Scenario: Owner only

- GIVEN a non-owner caller
- WHEN notifyRewardAmount(any) is called
- THEN the call MUST revert

### Requirement: recoverERC20 Exclusions

recoverERC20(token, amount) MUST be owner-only and MUST rescue only external tokens sent by mistake. It MUST revert for STK amounts that are staked principal or undistributed reward principal.

#### Scenario: Rescue external token

- GIVEN an unrelated token accidentally sent to the contract
- WHEN the owner calls recoverERC20 on that token
- THEN the amount MUST transfer to the owner

#### Scenario: STK principal excluded

- GIVEN STK balance held as staked principal and reward pool
- WHEN the owner calls recoverERC20 on STK
- THEN the call MUST revert

### Requirement: Security Posture

All mutative functions MUST follow checks-effects-interactions ordering, MUST be non-reentrant, MUST use SafeERC20 for token transfers, and MUST use 1e18-scaled fixed-point math under Solidity 0.8 checked arithmetic.

#### Scenario: Reentrancy blocked

- GIVEN a malicious contract staking
- WHEN it attempts to reenter withdraw or claimRewards during a call
- THEN the reentrant call MUST revert

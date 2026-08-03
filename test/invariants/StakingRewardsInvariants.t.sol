// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {StakingToken} from "../../src/StakingToken.sol";
import {StakingRewards} from "../../src/StakingRewards.sol";
import {Handler} from "./Handler.sol";

/// @notice Stateful invariant suite for StakingRewards (tasks 3.2–3.3).
/// @dev Financial-truth rules asserted after every random handler sequence:
///      solvency, accounting conservation, per-actor principal monotonicity,
///      lockup integrity, and rewards bounded by funding. Only the Handler may
///      touch the protocol — the raw contracts are excluded from fuzzing.
contract StakingRewardsInvariants is Test {
    StakingToken internal token;
    StakingRewards internal sr;
    Handler internal handler;

    uint256 internal constant LOCKUP_DURATION = 2_592_000; // 30 days
    uint256 internal constant STASH = 3_000_000 ether; // handler notify budget
    uint256 internal constant ACTOR_FUND = 500_000 ether;

    function setUp() public {
        token = new StakingToken();
        sr = new StakingRewards(address(token), address(this));
        handler = new Handler(sr, token, address(this));

        token.transfer(address(handler), STASH);
        for (uint256 i = 0; i < handler.ACTOR_COUNT(); i++) {
            token.transfer(handler.actors(i), ACTOR_FUND);
        }

        // Reach StakingRewards only through the handler's valid actor flows.
        targetContract(address(handler));
        excludeContract(address(sr));
        excludeContract(address(token));
    }

    /// @notice Solvency: the contract must always hold enough STK to cover every
    ///         staker's principal plus rewards committed but not yet paid out.
    /// @dev Rewards already paid left the contract, so the liability side is
    ///      principal + accrued-unpaid (emitted minus paid) — NOT principal +
    ///      cumulative paid (that sum exceeds the balance by construction).
    function invariant_solvency() public view {
        uint256 accruedUnpaid = handler.emittedGhost() - handler.rewardsPaid();
        assertGe(token.balanceOf(address(sr)), sr.totalStaked() + accruedUnpaid);
        // Principal alone is always fully backed.
        assertGe(token.balanceOf(address(sr)), sr.totalStaked());
    }

    /// @notice Accounting conservation: the internal total never drifts from the
    ///         sum of per-user balances.
    function invariant_accountingConservation() public view {
        uint256 sum;
        for (uint256 i = 0; i < handler.ACTOR_COUNT(); i++) {
            sum += sr.balances(handler.actors(i));
        }
        assertEq(sum, sr.totalStaked());
    }

    /// @notice Monotonic principal: a user's balance never exceeds their
    ///         cumulative deposits, and is exactly deposits minus withdrawals.
    function invariant_principalMonotonic() public view {
        for (uint256 i = 0; i < handler.ACTOR_COUNT(); i++) {
            address actor = handler.actors(i);
            assertLe(sr.balances(actor), handler.deposited(actor));
            assertEq(sr.balances(actor), handler.deposited(actor) - handler.withdrawn(actor));
        }
    }

    /// @notice Lockup integrity: lockupEndOf is always last-stake + 30 days, so
    ///         principal can never be withdrawn before that instant (the handler
    ///         models the same rule for its withdrawals).
    function invariant_lockupEndComputedFromStake() public view {
        for (uint256 i = 0; i < handler.ACTOR_COUNT(); i++) {
            address actor = handler.actors(i);
            if (handler.lastStakeTime(actor) > 0) {
                assertGe(sr.lockupEndOf(actor), handler.lastStakeTime(actor) + LOCKUP_DURATION);
            }
        }
    }

    /// @notice Rewards never exceed the funded pool: cumulative payouts are
    ///         bounded by what the owner pushed in and by committed emission.
    function invariant_rewardsBoundedByFunding() public view {
        assertLe(handler.rewardsPaid(), handler.fundedGhost());
        assertLe(handler.rewardsPaid(), handler.emittedGhost());
    }
}

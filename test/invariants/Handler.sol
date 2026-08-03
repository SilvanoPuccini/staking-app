// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {StakingToken} from "../../src/StakingToken.sol";
import {StakingRewards} from "../../src/StakingRewards.sol";

/// @title StakingRewards invariant handler (tasks 3.1–3.3)
/// @notice Drives StakingRewards through realistic actor flows — stake, claim,
///         withdraw, exit, owner notify — plus random time jumps, with bounded
///         amounts, so the stateful fuzzer explores reachable protocol states
///         instead of a heap of reverts.
/// @dev The handler exposes ONLY valid operations (amounts clamped to balances,
///      withdrawals gated on lockup expiry) and never asserts invariants itself
///      — it enables reachability; the invariant suite checks the truth.
///      Ghost variables track shadow accounting the suite compares against real
///      contract state: cumulative deposits/withdrawals per actor, rewards paid
///      out, funds pushed into the pool, and total committed emission.
contract Handler is Test {
    StakingRewards public immutable sr;
    StakingToken public immutable token;
    address public immutable owner;

    uint256 public constant ACTOR_COUNT = 4;
    uint256 public constant LOCKUP_DURATION = 2_592_000; // 30 days
    uint256 public constant REWARDS_DURATION = 7_776_000; // 90 days

    address[ACTOR_COUNT] public actors;

    // Ghosts — per actor.
    mapping(address => uint256) public deposited;
    mapping(address => uint256) public withdrawn;
    mapping(address => uint256) public lastStakeTime;

    // Ghosts — protocol-wide.
    /// @notice Total reward tokens transferred out to users (claims + exit rewards).
    uint256 public rewardsPaid;
    /// @notice Total STK pushed into the reward pool by owner-funded notifies.
    uint256 public fundedGhost;
    /// @notice Total committed emission so far (sum of rewardRate * REWARDS_DURATION per period).
    uint256 public emittedGhost;

    constructor(StakingRewards sr_, StakingToken token_, address owner_) {
        sr = sr_;
        token = token_;
        owner = owner_;
        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            actors[i] = address(uint160(uint256(keccak256(abi.encodePacked("staking.invariant.actor", i)))));
        }
    }

    /// @dev Actor i stakes a bounded amount of its own STK.
    function stake(uint256 seed) external {
        address actor = _pickActor(seed);
        uint256 available = token.balanceOf(actor);
        if (available == 0) return;
        uint256 amount = bound(seed >> 8, 1, available);

        vm.startPrank(actor);
        token.approve(address(sr), amount);
        sr.stake(amount);
        vm.stopPrank();

        deposited[actor] += amount;
        lastStakeTime[actor] = block.timestamp;
    }

    /// @dev Actor claims its accrued rewards at any time (allowed during lockup).
    function claim(uint256 seed) external {
        address actor = _pickActor(seed);
        if (sr.balances(actor) == 0) return;

        uint256 before = token.balanceOf(actor);
        vm.prank(actor);
        sr.claimRewards();
        rewardsPaid += token.balanceOf(actor) - before;
    }

    /// @dev Actor withdraws principal only once past its lockup end (modeled rule).
    function withdraw(uint256 seed) external {
        address actor = _pickActor(seed);
        if (block.timestamp < sr.lockupEndOf(actor)) return;
        uint256 bal = sr.balances(actor);
        if (bal == 0) return;
        uint256 amount = bound(seed >> 8, 1, bal);

        vm.prank(actor);
        sr.withdraw(amount);
        withdrawn[actor] += amount;
    }

    /// @dev Actor exits atomically (principal + rewards) only past lockup end.
    function exit(uint256 seed) external {
        address actor = _pickActor(seed);
        if (block.timestamp < sr.lockupEndOf(actor)) return;
        uint256 principal = sr.balances(actor);
        if (principal == 0) return;

        uint256 before = token.balanceOf(actor);
        vm.prank(actor);
        sr.exit();
        uint256 received = token.balanceOf(actor) - before;

        withdrawn[actor] += principal;
        rewardsPaid += received - principal;
    }

    /// @dev Owner pushes `amount` into the reward pool and starts a new period.
    function notify(uint256 seed) external {
        uint256 stash = token.balanceOf(address(this));
        if (stash == 0) return;
        uint256 amount = bound(seed, 1, stash);

        // Undistributed remainder of the current period — emission already
        // committed, so it must NOT be counted again for the new period.
        uint256 leftover = block.timestamp < sr.periodFinish()
            ? (sr.periodFinish() - block.timestamp) * sr.rewardRate()
            : 0;

        token.transfer(address(sr), amount);
        fundedGhost += amount;

        vm.prank(owner);
        sr.notifyRewardAmount(amount);

        // New committed emission excludes the recycled leftover. The integer
        // floor can drop part of the carryover (rate floors toward 0), so the
        // net delta may be negative — subtract branch-safely. emittedGhost is
        // always >= leftover (leftover is previously committed emission), so
        // this never underflows.
        uint256 newEmission = sr.rewardRate() * REWARDS_DURATION;
        if (newEmission >= leftover) {
            emittedGhost += newEmission - leftover;
        } else {
            emittedGhost -= leftover - newEmission;
        }
    }

    /// @dev Random time jump up to 45 days — crosses lockups and period ends.
    function warp(uint256 seed) external {
        vm.warp(block.timestamp + bound(seed, 0, 45 days));
    }

    function _pickActor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, ACTOR_COUNT - 1)];
    }
}

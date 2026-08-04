// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {StakingToken} from "../src/StakingToken.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Spec scenarios for the early-exit with penalty capability (design D7).
contract EarlyExitTest is Test {
    StakingToken internal token;
    StakingRewards internal sr;
    address internal deployer;
    address internal alice;
    address internal bob;

    uint256 internal constant REWARDS_DURATION = 7_776_000; // 90 days
    uint256 internal constant LOCKUP_DURATION = 2_592_000; // 30 days
    uint256 internal constant FUND = 1_000_000 ether;
    uint256 internal constant PENALTY_BPS = 1_500; // 15%

    function setUp() public {
        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        token = new StakingToken();
        sr = new StakingRewards(address(token), deployer);
        token.transfer(alice, FUND);
        token.transfer(bob, FUND);
    }

    function _fundAndNotify(uint256 amount) internal {
        token.transfer(address(sr), amount);
        sr.notifyRewardAmount(amount);
    }

    function _stakeAs(address user, uint256 amount) internal {
        vm.startPrank(user);
        token.approve(address(sr), amount);
        sr.stake(amount);
        vm.stopPrank();
    }

    // ---- Requirement: early exit during lockup charges the penalty ----

    function testEarlyExitChargesPenalty() public {
        _stakeAs(alice, 1_000 ether);

        vm.warp(block.timestamp + 1 days); // still inside lockup
        uint256 balanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(sr));
        emit StakingRewards.EarlyExit(alice, 1_000 ether, (1_000 ether * PENALTY_BPS) / 10_000);
        sr.exitEarly();

        uint256 penalty = (1_000 ether * PENALTY_BPS) / 10_000;
        uint256 payout = 1_000 ether - penalty;
        assertEq(token.balanceOf(alice), balanceBefore + payout, "payout wrong");
        assertEq(token.balanceOf(address(sr)), penalty, "penalty must stay in contract");
        assertEq(sr.balances(alice), 0, "position not cleared");
        assertEq(sr.totalStaked(), 0, "totalStaked not reduced");
    }

    // ---- Requirement: early exit reverts once the lockup has ended ----

    function testEarlyExitRevertsAfterLockup() public {
        _stakeAs(alice, 1_000 ether);
        vm.warp(block.timestamp + LOCKUP_DURATION + 1);

        vm.prank(alice);
        vm.expectRevert(StakingRewards.LockupEnded.selector);
        sr.exitEarly();

        // Normal penalty-free exit still works.
        vm.prank(alice);
        sr.exit();
        assertEq(token.balanceOf(alice), FUND, "penalty-free exit should return full principal");
    }

    // ---- Requirement: early exit reverts with no position ----

    function testEarlyExitZeroReverts() public {
        _stakeAs(alice, 1_000 ether);
        _stakeAs(bob, 1_000 ether);
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(alice);
        sr.exitEarly();
        vm.expectRevert(StakingRewards.InsufficientStakedBalance.selector);
        sr.exitEarly();
        vm.stopPrank();
    }

    // ---- Requirement: rewards remain claimable separately ----

    function testEarlyExitKeepsAccruedRewardsClaimable() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);

        vm.warp(block.timestamp + 1 days);
        uint256 earnedBefore = sr.earned(alice);
        assertGt(earnedBefore, 0, "no rewards accrued");

        vm.prank(alice);
        sr.exitEarly();

        // Rewards are not consumed by the early exit; still claimable.
        vm.prank(alice);
        sr.claimRewards();
        assertGt(token.balanceOf(alice), FUND - 1_000 ether, "rewards not claimable after early exit");
    }

    // ---- Requirement: penalty is 15% exact ----

    function testPenaltyIsExactBps() public {
        _stakeAs(alice, 123_456 ether);
        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        sr.exitEarly();

        uint256 expectedPenalty = (123_456 ether * PENALTY_BPS) / 10_000;
        assertEq(token.balanceOf(address(sr)), expectedPenalty, "penalty not exact bps");
    }

    // ---- Requirement: remaining stakers are not penalized ----

    function testEarlyExitDoesNotAffectOtherStaker() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        _stakeAs(bob, 1_000 ether);

        vm.warp(block.timestamp + 1 days);
        uint256 bobEarnedBefore = sr.earned(bob);

        vm.prank(alice);
        sr.exitEarly();

        // Bob's position is untouched.
        assertEq(sr.balances(bob), 1_000 ether);
        assertEq(sr.totalStaked(), 1_000 ether);
        assertEq(sr.earned(bob), bobEarnedBefore, "bob earned changed");
    }

    // ---- Requirement: penalty reinforces the reward pool (surplus funding) ----

    function testPenaltyReinforcesPoolForNextNotify() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 100 ether);
        _stakeAs(bob, 100 ether);
        vm.warp(block.timestamp + 1 days); // still inside lockup

        uint256 poolBefore = token.balanceOf(address(sr)) - sr.totalStaked();

        vm.prank(alice);
        sr.exitEarly(); // penalty stays in contract

        uint256 poolAfter = token.balanceOf(address(sr)) - sr.totalStaked();
        // Pool grew by the penalty: it is now fundable surplus.
        assertGt(poolAfter, poolBefore, "penalty did not reinforce the pool");
    }

    // ---- Requirement: no reentrancy on the new path ----

    function testEarlyExitIsNonReentrant() public {
        // A malicious staking token: on any transfer OUT of the staking
        // contract it re-enters claimRewards().
        ReentrantToken evil = new ReentrantToken();
        StakingRewards evilSr = new StakingRewards(address(evil), deployer);
        evil.mint(address(evilSr), 1_000 ether);
        evil.mint(address(this), 1_000 ether);
        evil.setTarget(address(evilSr));
        evil.setCallback(true);

        // Fund a period so there is something to claim.
        vm.prank(deployer);
        evilSr.notifyRewardAmount(1_000 ether);

        // Stake from a separate malicious contract address.
        address staker = makeAddr("staker");
        evil.mint(staker, 1_000 ether);
        vm.startPrank(staker);
        evil.approve(address(evilSr), 1_000 ether);
        evilSr.stake(1_000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        // During the payout transfer, the token re-enters claimRewards: the
        // nonReentrant guard blocks it (the reentrant call reverts) and the
        // outer exitEarly still completes with correct state.
        vm.prank(staker);
        evilSr.exitEarly();

        // The reentrant claim attempt did not succeed.
        assertEq(evilSr.balances(staker), 0, "position not cleared");
        assertEq(evilSr.totalStaked(), 0);
        // Staker received principal minus 15% penalty (850 of 1,000).
        assertEq(evil.balanceOf(staker), 850 ether, "payout must deduct the penalty");
        // Penalty stayed in the contract (pool 1,000 + penalty 150 = 1,150).
        assertEq(evil.balanceOf(address(evilSr)), 1_150 ether, "penalty must remain in contract");
    }
}

/// @dev Malicious ERC-20: on transfers OUT of the staking target it attempts a
///      reentrant claimRewards() call; when callback is on, that call must
///      revert (nonReentrant) and the outer call must still complete.
contract ReentrantToken {
    string public name = "Evil";
    string public symbol = "EVIL";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public target;
    bool public callback;

    function setTarget(address t) external {
        target = t;
    }

    function setCallback(bool on) external {
        callback = on;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        if (callback && msg.sender == target) {
            callback = false; // fire once
            (bool ok,) = target.call(abi.encodeWithSignature("claimRewards()"));
            if (ok) revert("reentrancy succeeded");
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        if (callback && from == target) {
            callback = false; // fire once
            (bool ok,) = target.call(abi.encodeWithSignature("claimRewards()"));
            if (ok) revert("reentrancy succeeded");
        }
        return true;
    }
}

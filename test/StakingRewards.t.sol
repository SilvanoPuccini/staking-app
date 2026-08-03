// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {StakingToken} from "../src/StakingToken.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Spec scenarios for the StakingRewards capability (specs/staking-rewards/spec.md).
contract StakingRewardsTest is Test {
    StakingToken internal token;
    StakingRewards internal sr;
    address internal deployer;
    address internal alice;
    address internal bob;
    address internal attacker;

    uint256 internal constant REWARDS_DURATION = 7_776_000; // 90 days
    uint256 internal constant LOCKUP_DURATION = 2_592_000; // 30 days
    uint256 internal constant FUND = 1_000_000 ether;

    function setUp() public {
        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        attacker = makeAddr("attacker");
        token = new StakingToken();
        sr = new StakingRewards(address(token), deployer);
        token.transfer(alice, FUND);
        token.transfer(bob, FUND);
    }

    /// @dev Owner funds the reward pool with `amount` and starts a new 90-day period.
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

    // ---- Requirement: Stake With Lockup ----

    function testFirstDepositUpdatesState() public {
        uint256 balBefore = token.balanceOf(alice);

        _stakeAs(alice, 1_000 ether);

        assertEq(sr.totalStaked(), 1_000 ether);
        assertEq(sr.balances(alice), 1_000 ether);
        assertEq(sr.lockupEndOf(alice), block.timestamp + LOCKUP_DURATION);
        assertEq(token.balanceOf(address(sr)), 1_000 ether);
        assertEq(token.balanceOf(alice), balBefore - 1_000 ether);
    }

    function testStakeZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(StakingRewards.StakeZero.selector);
        sr.stake(0);
    }

    // ---- Requirement: Time-Based Reward Accrual ----

    function testRewardsAccrueLinearly() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);

        vm.warp(block.timestamp + 1 days);

        // Spec formula: earned = (rewardPerToken * staked) / 1e18, where
        // rewardPerToken = elapsed * rewardRate * 1e18 / totalStaked (two-step scaling).
        uint256 expected = (sr.rewardRate() * 1 days * 1e18) / 1_000 ether * 1_000 ether / 1e18;
        assertGt(expected, 0);
        assertEq(sr.earned(alice), expected);
    }

    function testRewardPerTokenZeroTotalStakedReturnsStored() public {
        _fundAndNotify(FUND); // funded pool, no deposits

        assertEq(sr.rewardPerToken(), 0); // no division by zero; returns stored value
        vm.warp(block.timestamp + 10 days);
        assertEq(sr.rewardPerToken(), 0); // empty time skipped, stored unchanged
    }

    function testEmptyTimeBeforeStakeDoesNotAccrue() public {
        _fundAndNotify(FUND);
        vm.warp(block.timestamp + 45 days); // half the period with nobody staked
        _stakeAs(alice, 1_000 ether);

        vm.warp(block.timestamp + 1 days);

        // Only the day after staking accrues; the 45 empty days pay nothing.
        uint256 expected = (sr.rewardRate() * 1 days * 1e18) / 1_000 ether * 1_000 ether / 1e18;
        assertEq(sr.earned(alice), expected);
    }

    // ---- Requirement: Claim During Lockup ----

    function testClaimDuringLockupTransfersEarnedAndZeroes() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        vm.warp(block.timestamp + 1 days); // still inside the 30-day lockup

        uint256 expected = sr.earned(alice);
        assertGt(expected, 0);
        uint256 balBefore = token.balanceOf(alice);

        vm.prank(alice);
        sr.claimRewards();

        assertEq(token.balanceOf(alice), balBefore + expected);
        assertEq(sr.earned(alice), 0);
    }

    function testNoDoubleClaim() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        sr.claimRewards();
        uint256 balAfterFirst = token.balanceOf(alice);

        vm.prank(alice);
        sr.claimRewards();

        assertEq(token.balanceOf(alice), balAfterFirst); // nothing more transferred
        assertEq(sr.earned(alice), 0);
    }

    // ---- Requirement: Withdraw After Lockup ----

    function testWithdrawBlockedDuringLockup() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        vm.warp(block.timestamp + LOCKUP_DURATION / 2); // 15 days in

        vm.prank(alice);
        vm.expectRevert(StakingRewards.LockupNotEnded.selector);
        sr.withdraw(1 ether);
    }

    function testWithdrawAtLockupBoundary() public {
        _stakeAs(alice, 1_000 ether);
        vm.warp(sr.lockupEndOf(alice)); // exactly 30 days after the stake

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        sr.withdraw(1_000 ether);

        assertEq(token.balanceOf(alice), balBefore + 1_000 ether);
        assertEq(sr.totalStaked(), 0);
        assertEq(sr.balances(alice), 0);
    }

    function testWithdrawAfterLockupPartial() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        vm.warp(block.timestamp + 31 days);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        sr.withdraw(400 ether);

        assertEq(token.balanceOf(alice), balBefore + 400 ether);
        assertEq(sr.totalStaked(), 600 ether);
        assertEq(sr.balances(alice), 600 ether);
    }

    // ---- Requirement: exit ----

    function testExitDuringLockupReverts() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        vm.expectRevert(StakingRewards.LockupNotEnded.selector);
        sr.exit();
    }

    function testExitAfterLockupWithdrawsPrincipalAndClaims() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        vm.warp(block.timestamp + 31 days);

        uint256 expectedReward = sr.earned(alice);
        uint256 balBefore = token.balanceOf(alice);

        vm.prank(alice);
        sr.exit();

        assertEq(token.balanceOf(alice), balBefore + 1_000 ether + expectedReward);
        assertEq(sr.totalStaked(), 0);
        assertEq(sr.balances(alice), 0);
        assertEq(sr.earned(alice), 0);
    }

    // ---- Requirement: notifyRewardAmount ----

    function testNotifyInitialFundingSetsRate() public {
        token.transfer(address(sr), FUND);
        sr.notifyRewardAmount(FUND);

        assertEq(sr.rewardRate(), FUND / REWARDS_DURATION);
        assertEq(sr.periodFinish(), block.timestamp + REWARDS_DURATION);
    }

    function testNotifyTopUpCarriesOverLeftover() public {
        token.transfer(address(sr), FUND);
        sr.notifyRewardAmount(FUND);
        uint256 initialRate = sr.rewardRate();

        vm.warp(block.timestamp + 10 days);
        uint256 leftover = (sr.periodFinish() - block.timestamp) * initialRate;

        token.transfer(address(sr), 500_000 ether);
        sr.notifyRewardAmount(500_000 ether);

        assertEq(sr.rewardRate(), (500_000 ether + leftover) / REWARDS_DURATION);
        assertEq(sr.periodFinish(), block.timestamp + REWARDS_DURATION);
    }

    function testNotifyCappedByContractBalance() public {
        token.transfer(address(sr), 500 ether);
        sr.notifyRewardAmount(1_000 ether);

        assertEq(sr.rewardRate(), 500 ether / REWARDS_DURATION);
    }

    function testNotifyOwnerOnly() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        sr.notifyRewardAmount(1 ether);
    }

    // ---- Requirement: Reward pool exhaustion mid-period ----

    function testAccrualStopsWhenPeriodExhausted() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);

        vm.warp(block.timestamp + 100 days); // past periodFinish (90 days)

        uint256 earnedAtEnd = sr.earned(alice);
        // Sole staker of the full period: rewardPerToken reached rate * REWARDS_DURATION.
        assertEq(earnedAtEnd, (FUND / REWARDS_DURATION) * REWARDS_DURATION);

        vm.warp(block.timestamp + 5 days);
        assertEq(sr.earned(alice), earnedAtEnd); // accrual stopped after exhaustion
    }

    // ---- Requirement: recoverERC20 Exclusions ----

    function testRecoverExternalToken() public {
        MockToken mock = new MockToken();
        mock.transfer(address(sr), 100 ether);
        assertEq(mock.balanceOf(address(sr)), 100 ether);

        sr.recoverERC20(address(mock), 40 ether);

        assertEq(mock.balanceOf(address(sr)), 60 ether);
        assertEq(mock.balanceOf(deployer), 1_000_000 ether - 60 ether);
    }

    function testRecoverStakingTokenReverts() public {
        vm.expectRevert(StakingRewards.CannotRecoverStakingToken.selector);
        sr.recoverERC20(address(token), 1 ether);
    }

    function testRecoverNonOwnerReverts() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        sr.recoverERC20(address(token), 1 ether);
    }

    // ---- Requirement: Security Posture (reentrancy) ----

    function testReentrancyBlocked() public {
        MaliciousToken malicious = new MaliciousToken();
        StakingRewards sr2 = new StakingRewards(address(malicious), deployer);
        malicious.setTarget(sr2);
        malicious.transfer(alice, 1_000 ether);

        vm.startPrank(alice);
        malicious.approve(address(sr2), 1_000 ether);
        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        sr2.stake(100 ether);
        vm.stopPrank();
    }
}

/// @dev Harmless ERC-20 used to prove recoverERC20 rescues unrelated tokens.
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MCK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

/// @dev ERC-20 that attempts to reenter StakingRewards on any transfer into it.
contract MaliciousToken is ERC20 {
    StakingRewards public target;

    constructor() ERC20("Malicious Token", "MAL") {
        _mint(msg.sender, 100_000 ether);
    }

    function setTarget(StakingRewards target_) external {
        target = target_;
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (address(target) != address(0) && to == address(target)) {
            target.claimRewards(); // reentrancy attempt during any transfer into StakingRewards
        }
    }
}

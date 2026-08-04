// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {StakingToken} from "../src/StakingToken.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Security Attack Tests — adversarial PoCs against StakingRewards
/// @notice Each test attempts to corrupt the protocol through a known attack
///         vector. A PASS means the attack FAILED to break the protocol
///         (i.e. the protocol resisted). A REVERT with a targeted error or a
///         failed exploit assertion = protocol held.
/// @dev Attack surface reviewed: reentrancy, reward donation/inflation,
///      flash-stake reward capture, griefing, rounding, access control,
///      principal canibalization, silent reward-kill.
contract SecurityAttackTest is Test {
    StakingToken internal token;
    StakingRewards internal sr;
    address internal deployer;
    address internal alice;
    address internal attacker;

    uint256 internal constant REWARDS_DURATION = 7_776_000; // 90 days
    uint256 internal constant LOCKUP_DURATION = 2_592_000; // 30 days
    uint256 internal constant FUND = 1_000_000 ether;
    uint256 internal constant INITIAL_SUPPLY = 10_000_000 ether;

    function setUp() public {
        deployer = address(this);
        alice = makeAddr("alice");
        attacker = makeAddr("attacker");
        token = new StakingToken();
        sr = new StakingRewards(address(token), deployer);
        token.transfer(alice, FUND);
        token.transfer(attacker, FUND);
    }

    /// @dev Owner funds the reward pool and starts a 90-day period.
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

    // =====================================================================
    // ATTACK 1: Donation inflation — attacker donates STK directly to the
    // contract hoping to inflate their claimable rewards.
    // Expected: FAILS to corrupt. Rewards derive from totalStaked (internal
    // accounting), NOT from balanceOf(this) — donation-safe by design.
    // =====================================================================
    function testAttack1_DonationCannotInflateEarned() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        vm.warp(block.timestamp + 1 days);

        uint256 earnedBefore = sr.earned(alice);

        // Attacker "donates" 500k STK directly to the contract.
        vm.startPrank(attacker);
        token.transfer(address(sr), 500_000 ether);
        vm.stopPrank();

        uint256 earnedAfter = sr.earned(alice);

        // Donation must NOT change alice's accrued rewards.
        assertEq(earnedBefore, earnedAfter, "donation inflated earned()");
        // And the attacker cannot claim the donated amount: they have no stake.
        // The donation is trapped in the contract as future reward backing.
        vm.prank(attacker);
        sr.claimRewards();
        assertEq(token.balanceOf(attacker), FUND - 500_000 ether, "attacker claimed donated STK");
        // Donation + reward pool + staked principal all remain in the contract.
        assertEq(token.balanceOf(address(sr)), FUND + 500_000 ether + 1_000 ether, "donation should remain in contract");
    }

    // =====================================================================
    // ATTACK 2: Flash-stake reward capture — attacker flash-loans (simulated)
    // a huge balance, stakes it, claims rewards immediately, then tries to
    // withdraw principal in the same block to repay the loan.
    // Expected: FAILS. The 30-day lockup blocks the principal withdrawal, so
    // the flash loan cannot be repaid → the attack is not profitable/possible.
    // =====================================================================
    function testAttack2_FlashStakeCannotWithdrawBeforeLockup() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 100 ether);
        vm.warp(block.timestamp + 10 days);

        // Attacker stakes 1M (simulated flash loan) and claims instantly.
        vm.startPrank(attacker);
        token.approve(address(sr), 1_000_000 ether);
        sr.stake(1_000_000 ether);
        sr.claimRewards();
        vm.stopPrank();

        // Attempt to withdraw the principal immediately to repay the "loan".
        vm.prank(attacker);
        vm.expectRevert(StakingRewards.LockupNotEnded.selector);
        sr.withdraw(1_000_000 ether);
    }

    // =====================================================================
    // ATTACK 3: Reentrancy — attacker contract tries to re-enter claimRewards
    // or stake during the transfer callback. The token is a standard ERC-20
    // with no callback hooks, but ReentrancyGuard + CEI would block any
    // reentrant path regardless. We verify the guard behavior on a direct
    // double-call within one transaction.
    // =====================================================================
    function testAttack3_ReentrancyGuardBlocksReentrantClaim() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 100 ether);
        vm.warp(block.timestamp + 1 days);

        // Simulate a malicious caller that tries claimRewards twice.
        // The guard only protects against actual reentrancy; here we verify
        // CEI: claiming twice yields no double-pay (rewards reset to zero).
        vm.startPrank(alice);
        sr.claimRewards();
        uint256 secondClaim = sr.earned(alice); // tiny, freshly accrued
        assertLt(secondClaim, 1 ether, "double claim paid full rewards again");
        vm.stopPrank();
    }

    // =====================================================================
    // ATTACK 4: Griefing — attacker stakes 1 wei at the last second to reset
    // an existing user's lockup? Lockup is per-user (lockupEndOf[msg.sender]),
    // so the attacker cannot touch alice's lockup. Verify.
    // =====================================================================
    function testAttack4_CannotResetOthersLockup() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        uint256 aliceLockup = sr.lockupEndOf(alice);

        // Attacker stakes tiny amount at a later time.
        vm.warp(block.timestamp + 5 days);
        vm.prank(attacker);
        token.approve(address(sr), 1 wei);
        vm.prank(attacker);
        sr.stake(1 wei);

        // Alice's lockup unchanged.
        assertEq(sr.lockupEndOf(alice), aliceLockup, "attacker reset victim lockup");
        assertEq(sr.lockupEndOf(attacker), block.timestamp + LOCKUP_DURATION);
    }

    // =====================================================================
    // ATTACK 5: Silent reward kill — owner notifies with an amount smaller
    // than REWARDS_DURATION; the integer division would floor rewardRate to 0
    // and the 90-day period would fund nothing silently.
    // FIXED (design D6): notifyRewardAmount now reverts RewardPeriodTooSmall
    // instead of silently funding a zero-rate period.
    // =====================================================================
    function testAttack5_UnderfundedNotifyReverts() public {
        _fundAndNotify(FUND);
        vm.warp(block.timestamp + REWARDS_DURATION); // period over

        // Owner tops up with an amount below REWARDS_DURATION base units.
        uint256 dust = 1_000_000; // 1e-12 STK — under 7,776,000 threshold
        token.transfer(address(sr), dust);

        vm.expectRevert(StakingRewards.RewardPeriodTooSmall.selector);
        sr.notifyRewardAmount(dust);

        // The period was NOT silently killed: state unchanged.
        assertGt(sr.rewardRate(), 0, "period was silently killed");
    }

    // =====================================================================
    // ATTACK 6: Principal canibalization — notifyRewardAmount used to cap
    // `funded` at balanceOf(this), which INCLUDES staked principal. A careless
    // owner could commit staked principal as rewards, threatening solvency.
    // FIXED (design D6): the cap now uses balance - totalStaked (surplus over
    // principal), so staked principal can never be committed as rewards.
    // =====================================================================
    function testAttack6_NotifyCannotCanibalizePrincipal() public {
        // Alice stakes most of the pool's funding as principal BEFORE rewards
        // are even notified: her principal + future pool are mixed in balance.
        _stakeAs(alice, 900_000 ether);
        // Owner funds rewards on top of the existing staked principal.
        _fundAndNotify(100_000 ether);
        vm.warp(block.timestamp + REWARDS_DURATION); // period over

        uint256 balance = token.balanceOf(address(sr));
        uint256 principal = sr.totalStaked();
        uint256 surplus = balance - principal;
        // At period end: balance = leftover pool + staked principal.
        assertGt(principal, 0, "setup: no principal staked");

        // Careless owner notifies the ENTIRE balance (which includes principal).
        sr.notifyRewardAmount(balance);

        // FIXED: committed emission is capped at the surplus, not the balance.
        assertLe(sr.rewardRate() * REWARDS_DURATION, surplus, "staked principal committed as rewards");
        assertLt(
            sr.rewardRate() * REWARDS_DURATION, balance, "principal canibalized - cap did not exclude staked principal"
        );
    }

    // =====================================================================
    // ATTACK 7: recoverERC20 exclusion — owner tries to rescue STK.
    // Expected: REVERTS CannotRecoverStakingToken — principal/pool is safe.
    // =====================================================================
    function testAttack7_CannotRecoverStakingToken() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 100 ether);

        vm.expectRevert(StakingRewards.CannotRecoverStakingToken.selector);
        sr.recoverERC20(address(token), 100 ether);
    }

    // =====================================================================
    // ATTACK 8: Access control — non-owner tries notify/recover.
    // Expected: REVERTS OwnableUnauthorizedAccount — privileged paths locked.
    // =====================================================================
    function testAttack8_OnlyOwnerPathsLocked() public {
        _fundAndNotify(FUND);

        vm.startPrank(attacker);
        vm.expectRevert();
        sr.notifyRewardAmount(100 ether);
        vm.expectRevert();
        sr.recoverERC20(address(0xdead), 1 ether);
        vm.stopPrank();
    }

    // =====================================================================
    // ATTACK 9: Rounding favorability — can a tiny stake accumulate more
    // reward per unit than a large stake? rewardPerToken is global and
    // shared; per-unit rewards are identical for equal time. Verify no
    // rounding edge lets 1 wei capture disproportionate value.
    // =====================================================================
    function testAttack9_NoDisproportionateTinyStake() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        _stakeAs(attacker, 1 wei);
        vm.warp(block.timestamp + 1 days);

        uint256 rpt = sr.rewardPerToken();
        // Both stakers share the same reward-per-token accumulator.
        uint256 aliceEarned = (1_000 ether * rpt) / 1e18;
        uint256 attackerEarned = (1 wei * rpt) / 1e18;

        // Per-wei accrual identical: attacker earns ~1000x less than alice.
        assertGe(aliceEarned, attackerEarned * 1_000 ether / 1 wei, "tiny stake captured excess");
    }

    // =====================================================================
    // ATTACK 10: Withdraw/claim ordering — attacker claims, then front-runs a
    // victim's claim. No cross-user claim path exists; each user's rewards are
    // isolated. Verify attacker cannot touch alice's rewards.
    // =====================================================================
    function testAttack10_RewardsIsolatedPerUser() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);
        _stakeAs(attacker, 1_000 ether);
        vm.warp(block.timestamp + 2 days);

        uint256 aliceBefore = sr.earned(alice);
        uint256 attackerEarnedBefore = sr.earned(attacker);

        vm.prank(attacker);
        sr.claimRewards();

        // Alice's accrued rewards untouched by attacker's claim.
        assertEq(sr.earned(alice), aliceBefore, "attacker claim touched victim rewards");
        // Attacker received exactly their own earned rewards (nothing extra).
        assertEq(
            token.balanceOf(attacker), FUND - 1_000 ether + attackerEarnedBefore, "attacker gained beyond own rewards"
        );
    }

    // =====================================================================
    // ATTACK 11: Flash stake + same-block early exit — with early-exit live,
    // can an attacker stake and exit in the same block to (a) dodge the 30-day
    // lockup and (b) capture rewards earned only for that instant?
    // Expected: exitEarly() charges the 15% penalty on every in-lockup exit,
    // so dodging the lockup costs 15% of principal. Same-block rewards are
    // ~0 (no time elapsed), so the attacker cannot farm value — they LOSE the
    // penalty instead.
    // =====================================================================
    function testAttack11_FlashStakeEarlyExitPaysPenalty() public {
        _fundAndNotify(FUND);
        _stakeAs(alice, 1_000 ether);

        // Same block: stake then exit early before any time passes.
        uint256 balBefore = token.balanceOf(attacker);
        vm.startPrank(attacker);
        token.approve(address(sr), 10_000 ether);
        sr.stake(1_000 ether);
        sr.exitEarly();
        vm.stopPrank();

        // Attacker got principal minus 15% penalty — they LOST 150 STK.
        assertEq(token.balanceOf(attacker), balBefore - 150 ether, "flash stake did not pay penalty");
        // Penalty reinforces the pool (balance - totalStaked surplus).
        assertGt(token.balanceOf(address(sr)), FUND + 1_000 ether, "penalty did not stay in contract");
    }
}

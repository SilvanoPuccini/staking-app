// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {StakingToken} from "../src/StakingToken.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Governance integration: StakingRewards v2 is owned by a
///         TimelockController, so every owner action (notify/recover) is
///         delayed. The bootstrap period starts immediately at deploy, then
///         ownership is handed to the timelock (script/DeployV2.s.sol).
contract TimelockTest is Test {
    StakingToken internal token;
    StakingRewards internal sr;
    TimelockController internal timelock;
    address internal deployer;
    address internal attacker;

    uint256 internal constant REWARDS_DURATION = 7_776_000; // 90 days
    uint256 internal constant MIN_DELAY = 2 days;
    uint256 internal constant FUND = 1_000_000 ether;

    function setUp() public {
        deployer = address(this);
        attacker = makeAddr("attacker");
        token = new StakingToken();
        sr = new StakingRewards(address(token), deployer);

        // Governance setup mirrors DeployV2: deployer proposes AND executes;
        // admin role is burned (address(0)).
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = deployer;
        timelock = new TimelockController(MIN_DELAY, proposers, executors, address(0));

        // Bootstrap: fund pool + start period 1 while deployer is owner...
        token.transfer(address(sr), FUND);
        sr.notifyRewardAmount(FUND);
        // ...then hand governance to the timelock.
        sr.transferOwnership(address(timelock));
    }

    // ---- Requirement: owner actions are timelocked after bootstrap ----

    function testOwnerIsTimelockAfterHandover() public view {
        assertEq(sr.owner(), address(timelock), "owner should be the timelock");
    }

    function testDeployerCannotNotifyDirectlyAfterHandover() public {
        uint256 topUp = 100 ether;
        token.transfer(address(sr), topUp);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, deployer));
        sr.notifyRewardAmount(topUp);
    }

    function testNotifyRequiresScheduleWaitExecute() public {
        uint256 topUp = 100 ether;
        token.transfer(address(sr), topUp);
        bytes memory data = abi.encodeWithSelector(StakingRewards.notifyRewardAmount.selector, topUp);

        // Deployer schedules as proposer.
        vm.prank(deployer);
        timelock.schedule(address(sr), 0, data, bytes32(0), keccak256("notify-1"), MIN_DELAY);

        // Cannot execute before the delay elapses: execute reverts
        // TimelockUnexpectedOperationState(id, Ready-bitmap) when not Ready.
        bytes32 opId = timelock.hashOperation(address(sr), 0, data, bytes32(0), keccak256("notify-1"));
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                opId,
                bytes32(uint256(1) << 2) // OperationState.Ready bit
            )
        );
        timelock.execute(address(sr), 0, data, bytes32(0), keccak256("notify-1"));

        // After minDelay, execution succeeds and starts a fresh period.
        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(deployer);
        timelock.execute(address(sr), 0, data, bytes32(0), keccak256("notify-1"));

        assertGt(sr.rewardRate(), 0, "timelocked notify did not start a period");
    }

    function testOperationIsDoneAfterExecute() public {
        uint256 topUp = 1 ether;
        token.transfer(address(sr), topUp);
        bytes memory data = abi.encodeWithSelector(StakingRewards.notifyRewardAmount.selector, topUp);
        bytes32 salt = keccak256("notify-done");
        bytes32 opId = timelock.hashOperation(address(sr), 0, data, bytes32(0), salt);

        vm.prank(deployer);
        timelock.schedule(address(sr), 0, data, bytes32(0), salt, MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(deployer);
        timelock.execute(address(sr), 0, data, bytes32(0), salt);

        assertTrue(timelock.isOperationDone(opId), "operation should be done after execute");
    }

    // ---- Requirement: attacker cannot touch the timelock ----

    function testAttackerCannotSchedule() public {
        bytes memory data = abi.encodeWithSelector(StakingRewards.notifyRewardAmount.selector, 1 ether);

        vm.prank(attacker);
        vm.expectRevert();
        timelock.schedule(address(sr), 0, data, bytes32(0), keccak256("attacker-notify"), MIN_DELAY);
    }

    function testAttackerCannotExecute() public {
        uint256 topUp = 1 ether;
        token.transfer(address(sr), topUp);
        bytes memory data = abi.encodeWithSelector(StakingRewards.notifyRewardAmount.selector, topUp);

        vm.prank(deployer);
        timelock.schedule(address(sr), 0, data, bytes32(0), keccak256("notify-2"), MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY);

        vm.prank(attacker);
        vm.expectRevert();
        timelock.execute(address(sr), 0, data, bytes32(0), keccak256("notify-2"));
    }

    // ---- Requirement: recovery is also timelocked ----

    function testRecoverERC20IsTimelocked() public {
        // A random token gets stuck in the staking contract.
        MockToken stuck = new MockToken();
        stuck.mint(address(sr), 50 ether);
        bytes memory data = abi.encodeWithSelector(StakingRewards.recoverERC20.selector, address(stuck), 50 ether);

        // Direct owner call no longer works (owner is the timelock).
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, deployer));
        sr.recoverERC20(address(stuck), 50 ether);

        // Timelocked recovery works after the delay; funds go to the owner
        // (the timelock itself).
        vm.prank(deployer);
        timelock.schedule(address(sr), 0, data, bytes32(0), keccak256("recover-1"), MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(deployer);
        timelock.execute(address(sr), 0, data, bytes32(0), keccak256("recover-1"));

        assertEq(stuck.balanceOf(address(timelock)), 50 ether, "recovery did not reach owner");
    }

    // ---- Requirement: hardened notify semantics survive through the timelock ----

    function testTimelockedNotifyStillRevertsWhenUnderfunded() public {
        // Let period 1 fully elapse so leftover = 0, then schedule a dust top-up:
        // through the timelock it must still revert RewardPeriodTooSmall.
        vm.warp(block.timestamp + REWARDS_DURATION);

        uint256 dust = 1_000_000; // below REWARDS_DURATION
        token.transfer(address(sr), dust);
        bytes memory data = abi.encodeWithSelector(StakingRewards.notifyRewardAmount.selector, dust);

        vm.prank(deployer);
        timelock.schedule(address(sr), 0, data, bytes32(0), keccak256("dust-notify"), MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY);

        vm.prank(deployer);
        vm.expectRevert(StakingRewards.RewardPeriodTooSmall.selector);
        timelock.execute(address(sr), 0, data, bytes32(0), keccak256("dust-notify"));
    }
}

/// @dev Minimal ERC-20 used to test recoverERC20 through the timelock.
contract MockToken {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

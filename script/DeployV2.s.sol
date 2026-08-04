// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Script, console2} from "forge-std/Script.sol";
import {StakingToken} from "../src/StakingToken.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Staking Protocol v2 deployment (hardened + governance)
/// @notice Deploys the v2 stack: StakingRewards (hardened contract, commit
///         ad1203f) with a TimelockController as its owner.
///
/// Governance flow:
///   1. StakingRewards is deployed with the deployer as initial owner and the
///      first 90-day reward period starts immediately (notifyRewardAmount).
///   2. Ownership is then transferred to the TimelockController (minDelay 2d):
///      every future notify/recover must be scheduled, wait, then execute —
///      an owner mistake is no longer instantaneous.
///
/// Token reuse: pass TOKEN_ADDRESS to reuse the already-deployed StakingToken
/// (Sepolia: 0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5). Omit it to deploy a
/// fresh token (anvil/local).
contract DeployV2 is Script {
    /// @notice Initial reward pool funding: 1,000,000 STK (10% of the 10M supply).
    uint256 public constant REWARD_POOL = 1_000_000e18;
    /// @notice Governance delay: 2 days — every owner action waits this long.
    uint256 public constant MIN_DELAY = 2 days;

    function run() external returns (StakingRewards sr, TimelockController timelock) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);

        // --- Token: reuse the deployed one (Sepolia) or deploy fresh (anvil). ---
        StakingToken token;
        address tokenAddr = vm.envOr("TOKEN_ADDRESS", address(0));
        if (tokenAddr != address(0)) {
            token = StakingToken(tokenAddr);
            console2.log("Reusing StakingToken:", address(token));
        } else {
            token = new StakingToken();
            console2.log("Deployed new StakingToken:", address(token));
        }

        // --- StakingRewards v2: hardened code, deployer as bootstrap owner. ---
        sr = new StakingRewards(address(token), deployer);
        console2.log("StakingRewards v2:", address(sr));

        // --- TimelockController: 2-day delay; deployer proposes and executes. ---
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = deployer;
        // admin = address(0) locks the admin role after setup (OZ recommendation).
        timelock = new TimelockController(MIN_DELAY, proposers, executors, address(0));
        console2.log("TimelockController:", address(timelock));

        // --- Fund the reward pool and start period 1 while deployer is owner. ---
        token.transfer(address(sr), REWARD_POOL);
        sr.notifyRewardAmount(REWARD_POOL);

        // --- Hand governance to the timelock: future owner actions are delayed. ---
        sr.transferOwnership(address(timelock));
        require(sr.owner() == address(timelock), "ownership handover failed");

        vm.stopBroadcast();
    }
}

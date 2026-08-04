// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Script, console2} from "forge-std/Script.sol";
import {StakingToken} from "../src/StakingToken.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Staking Protocol v3 deployment (early-exit + governance)
/// @notice Deploys the v3 stack: StakingRewards with the early-exit-with-penalty
///         capability (design D7), governed by the SAME TimelockController as v2
///         (single governance point — the deployer is already proposer/executor).
///
/// Governance flow:
///   1. StakingRewards v3 is deployed with the deployer as initial owner and the
///      first 90-day reward period starts immediately (notifyRewardAmount).
///   2. Ownership is transferred to the timelock: future notify/recover actions
///      must be scheduled, wait 2 days, then execute.
///
/// Token reuse: pass TOKEN_ADDRESS to reuse the already-deployed StakingToken
/// (Sepolia: 0xb8EaDA40EccA1c4E71Ed80F6C09A7C063f790dc5). Omit it to deploy a
/// fresh token (anvil/local).
/// Timelock reuse: pass TIMELOCK_ADDRESS to reuse an existing timelock (Sepolia:
/// 0x018efb5099505113625dabc5dc6f5513ad252c6b from v2). Omit it to deploy a new
/// one (anvil/local).
contract DeployV3 is Script {
    /// @notice Initial reward pool funding: 1,000,000 STK (10% of the 10M supply).
    uint256 public constant REWARD_POOL = 1_000_000e18;
    /// @notice Governance delay: 2 days — every owner action waits this long.
    uint256 public constant MIN_DELAY = 2 days;
    /// @notice Early-exit penalty: 15% withheld from principal during lockup.
    uint256 public constant PENALTY_BPS = 1_500;

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

        // --- Timelock: reuse v2's (Sepolia) or deploy fresh (anvil). ---
        address timelockAddr = vm.envOr("TIMELOCK_ADDRESS", address(0));
        if (timelockAddr != address(0)) {
            timelock = TimelockController(payable(timelockAddr));
            console2.log("Reusing TimelockController:", address(timelock));
        } else {
            address[] memory proposers = new address[](1);
            proposers[0] = deployer;
            address[] memory executors = new address[](1);
            executors[0] = deployer;
            timelock = new TimelockController(MIN_DELAY, proposers, executors, address(0));
            console2.log("Deployed new TimelockController:", address(timelock));
        }

        // --- StakingRewards v3: early-exit + hardened code, deployer owner. ---
        sr = new StakingRewards(address(token), deployer);
        console2.log("StakingRewards v3:", address(sr));
        console2.log("PENALTY_BPS:", sr.PENALTY_BPS());

        // --- Fund the reward pool and start period 1 while deployer is owner. ---
        token.transfer(address(sr), REWARD_POOL);
        sr.notifyRewardAmount(REWARD_POOL);

        // --- Hand governance to the timelock: future owner actions are delayed. ---
        sr.transferOwnership(address(timelock));
        require(sr.owner() == address(timelock), "ownership handover failed");

        vm.stopBroadcast();
    }
}

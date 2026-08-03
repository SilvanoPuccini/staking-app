// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Script, console2} from "forge-std/Script.sol";
import {StakingToken} from "../src/StakingToken.sol";
import {StakingRewards} from "../src/StakingRewards.sol";

/// @title Staking Protocol deployment (task 3.4)
/// @notice Deploys the full v1 stack on an anvil/local chain:
///         StakingToken → StakingRewards(token, deployer) → fund the reward
///         pool with 1,000,000 STK → notifyRewardAmount(1_000_000e18) to start
///         the first 90-day emission period.
/// @dev Requires a funded deployer key. Local smoke run:
///      `PRIVATE_KEY=<anvil-key-0> forge script script/Deploy.s.sol \
///       --rpc-url http://127.0.0.1:8545 --broadcast`
contract Deploy is Script {
    /// @notice Initial reward pool funding: 1,000,000 STK (10% of the 10M supply).
    uint256 public constant REWARD_POOL = 1_000_000e18;

    function run() external returns (StakingToken token, StakingRewards sr) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        // Derive the owner explicitly: during simulation msg.sender of `new`
        // deployments is forge's default sender, not the broadcast key address.
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);

        token = new StakingToken();
        // Owner is the broadcast sender (the deployer), matching Ownable(initialOwner).
        sr = new StakingRewards(address(token), deployer);

        // Fund the reward pool, then start the first 90-day period.
        token.transfer(address(sr), REWARD_POOL);
        sr.notifyRewardAmount(REWARD_POOL);

        vm.stopBroadcast();

        console2.log("StakingToken:", address(token));
        console2.log("StakingRewards:", address(sr));
    }
}

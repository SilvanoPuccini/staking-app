// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title StakingApp Token (STK)
/// @notice Fixed-supply ERC-20 asset backing the staking protocol.
/// @dev The full supply is minted once to the deployer; no mint or burn exists,
///      so the supply is immutable after deployment.
contract StakingToken is ERC20 {
    /// @notice Total supply: 10,000,000 STK in base units (18 decimals).
    uint256 public constant INITIAL_SUPPLY = 10_000_000 * 1e18;

    constructor() ERC20("StakingApp Token", "STK") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}

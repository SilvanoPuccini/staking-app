// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {StakingToken} from "../src/StakingToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @notice Spec scenarios for the StakingToken capability (specs/staking-token/spec.md).
contract StakingTokenTest is Test {
    StakingToken internal token;
    address internal deployer;
    address internal alice;
    address internal bob;

    uint256 internal constant INITIAL_SUPPLY = 10_000_000 * 1e18;

    function setUp() public {
        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        token = new StakingToken();
    }

    // ---- Requirement: ERC-20 Metadata ----

    function testMetadata() public view {
        assertEq(token.name(), "StakingApp Token");
        assertEq(token.symbol(), "STK");
        assertEq(token.decimals(), 18);
    }

    // ---- Requirement: Fixed Supply Minted Once ----

    function testDeployerReceivesFullSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(deployer), INITIAL_SUPPLY);
    }

    function testCannotMintNewSupply() public {
        // No mint function exists: a low-level call to a nonexistent selector must revert.
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", alice, 1e18));
        assertFalse(ok);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(deployer), INITIAL_SUPPLY);
    }

    // ---- Requirement: Transfers and Allowances ----

    function testTransferUpdatesBalancesAndEmitsEvent() public {
        token.transfer(alice, 1_000 ether);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(alice, bob, 400 ether);

        token.transfer(bob, 400 ether);

        assertEq(token.balanceOf(alice), 600 ether);
        assertEq(token.balanceOf(bob), 400 ether);
    }

    function testTransferWithoutBalanceReverts() public {
        token.transfer(alice, 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 100 ether, 101 ether)
        );
        token.transfer(bob, 101 ether);
    }

    function testApproveSetsAllowanceAndEmitsEvent() public {
        token.transfer(alice, 1_000 ether);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(alice, bob, 500 ether);

        token.approve(bob, 500 ether);

        assertEq(token.allowance(alice, bob), 500 ether);
    }

    function testTransferFromSpendsAllowance() public {
        token.transfer(alice, 1_000 ether);

        vm.prank(alice);
        token.approve(bob, 500 ether);

        vm.prank(bob);
        token.transferFrom(alice, bob, 400 ether);

        assertEq(token.balanceOf(alice), 600 ether);
        assertEq(token.balanceOf(bob), 400 ether);
        assertEq(token.allowance(alice, bob), 100 ether);
    }

    function testTransferFromWithoutAllowanceReverts() public {
        token.transfer(alice, 100 ether);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 10 ether));
        token.transferFrom(alice, bob, 10 ether);
    }
}

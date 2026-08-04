# StakingToken Specification

## Purpose

StakingApp Token (STK) is the protocol's ERC-20 asset: a fixed supply of 10,000,000 STK (10,000,000 * 1e18 base units) minted once at deployment, with no further issuance. It backs both staking and reward payments in the staking protocol.

## Requirements

### Requirement: ERC-20 Metadata

The token MUST implement the ERC-20 standard with name "StakingApp Token", symbol "STK", and 18 decimals.

#### Scenario: Standard metadata exposed

- GIVEN a deployed StakingToken
- WHEN name(), symbol(), and decimals() are queried
- THEN they MUST return "StakingApp Token", "STK", and 18 respectively

### Requirement: Fixed Supply Minted Once

The constructor MUST mint exactly 10,000,000 * 1e18 STK to the deployer. The token MUST NOT allow further minting or burning.

#### Scenario: Deployer receives full supply

- GIVEN a StakingToken deployed by an account
- WHEN totalSupply() and balanceOf(deployer) are queried
- THEN both MUST equal 10,000,000 * 1e18

#### Scenario: No further issuance

- GIVEN the deployed token
- WHEN any account attempts to increase supply
- THEN the attempt MUST fail because no mint function exists

### Requirement: Transfers and Allowances

The token MUST implement ERC-20 transfer, approve, and transferFrom with standard semantics, MUST emit Transfer and Approval events, and MUST revert on insufficient balance or allowance.

#### Scenario: Transfer updates balances

- GIVEN a holder with 1,000 STK
- WHEN the holder transfers 400 STK to a recipient
- THEN holder and recipient balances MUST change by 400
- AND a Transfer event MUST be emitted

#### Scenario: Transfer without balance reverts

- GIVEN an account holding 100 STK
- WHEN it transfers 101 STK
- THEN the call MUST revert

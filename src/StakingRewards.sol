// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StakingRewards
/// @notice STK staking with a 30-day minimum lockup and time-based rewards paid
///         in the same token from a pre-funded pool.
/// @dev Synthetix-style reward-per-share accumulator. Rewards accrue per second and
///      are claimable at any time; only principal withdrawal is deferred until
///      lockupEndOf(user). CEI ordering, ReentrancyGuard, SafeERC20, Ownable,
///      1e18-scaled fixed-point math under Solidity 0.8 checked arithmetic.
contract StakingRewards is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice 90 days in seconds — the reward emission window per notify.
    uint256 public constant REWARDS_DURATION = 7_776_000;
    /// @notice 30 days in seconds — minimum principal lockup per stake.
    uint256 public constant LOCKUP_DURATION = 2_592_000;

    /// @notice The staking token; also the reward token (same-token rewards).
    IERC20 public immutable stakingToken;

    /// @notice Timestamp when the current emission period ends.
    uint256 public periodFinish;
    /// @notice Reward tokens emitted per second during the period.
    uint256 public rewardRate;
    /// @notice Last timestamp at which the accumulator was checkpointed.
    uint256 public lastUpdateTime;
    /// @notice Global reward-per-token accumulator (1e18-scaled).
    uint256 public rewardPerTokenStored;
    /// @notice Total staked principal across all users (internal accounting).
    uint256 public totalStaked;

    /// @notice Staked principal per user.
    mapping(address => uint256) public balances;
    /// @notice Timestamp after which each user may withdraw principal.
    mapping(address => uint256) public lockupEndOf;
    /// @notice Claimable rewards already checkpointed per user.
    mapping(address => uint256) private _rewards;
    /// @notice Reward-per-token checkpoint per user.
    mapping(address => uint256) private _userRewardPerTokenPaid;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event Recovered(address indexed token, uint256 amount);

    error ZeroAddress();
    error StakeZero();
    error LockupNotEnded();
    error InsufficientStakedBalance();
    error CannotRecoverStakingToken();

    constructor(address stakingToken_, address initialOwner) Ownable(initialOwner) {
        if (stakingToken_ == address(0)) revert ZeroAddress();
        stakingToken = IERC20(stakingToken_);
    }

    /// @notice Latest timestamp at which rewards apply (period-end aware).
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Global reward-per-token accumulator; frozen while totalStaked is zero.
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalStaked;
    }

    /// @notice Total claimable rewards for `account` (checkpointed + accrued).
    function earned(address account) public view returns (uint256) {
        return (balances[account] * (rewardPerToken() - _userRewardPerTokenPaid[account])) / 1e18 + _rewards[account];
    }

    /// @notice Deposit `amount` STK under a fresh 30-day lockup.
    /// @dev Repeated stakes extend the whole position's lockup (design D3).
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert StakeZero();
        balances[msg.sender] += amount;
        totalStaked += amount;
        lockupEndOf[msg.sender] = block.timestamp + LOCKUP_DURATION;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /// @notice Withdraw `amount` principal; reverts until lockupEndOf(caller).
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        if (block.timestamp < lockupEndOf[msg.sender]) revert LockupNotEnded();
        if (balances[msg.sender] < amount) revert InsufficientStakedBalance();
        balances[msg.sender] -= amount;
        totalStaked -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Transfer all earned rewards to the caller. Allowed at any time,
    ///         including during lockup; only principal is locked.
    function claimRewards() public nonReentrant updateReward(msg.sender) {
        uint256 reward = _rewards[msg.sender];
        if (reward > 0) {
            _rewards[msg.sender] = 0;
            stakingToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Atomic exit: claim rewards and withdraw full principal in one call.
    /// @dev Reverts before lockupEndOf(caller); use claimRewards() meanwhile (design D4).
    function exit() external nonReentrant updateReward(msg.sender) {
        if (block.timestamp < lockupEndOf[msg.sender]) revert LockupNotEnded();
        uint256 principal = balances[msg.sender];
        uint256 reward = _rewards[msg.sender];
        balances[msg.sender] = 0;
        totalStaked -= principal;
        _rewards[msg.sender] = 0;
        if (principal > 0) {
            stakingToken.safeTransfer(msg.sender, principal);
            emit Withdrawn(msg.sender, principal);
        }
        if (reward > 0) {
            stakingToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Fund a new 90-day emission period (owner only).
    /// @dev Synthetix top-up: any undistributed remainder of the current period is
    ///      carried over, and the total is capped at the contract's STK balance
    ///      (design D1). updateReward(address(0)) checkpoints global state first.
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        uint256 leftover = block.timestamp < periodFinish ? (periodFinish - block.timestamp) * rewardRate : 0;
        uint256 funded = reward + leftover;
        uint256 balance = stakingToken.balanceOf(address(this));
        if (funded > balance) {
            funded = balance;
        }
        rewardRate = funded / REWARDS_DURATION;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + REWARDS_DURATION;
        emit RewardAdded(reward);
    }

    /// @notice Rescue tokens accidentally sent to the contract (owner only).
    /// @dev STK is always excluded: it backs staked principal and the reward pool
    ///      (design D5). STK donations fund future rewards instead.
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        if (token == address(stakingToken)) revert CannotRecoverStakingToken();
        IERC20(token).safeTransfer(owner(), amount);
        emit Recovered(token, amount);
    }

    /// @dev Checkpoint the global accumulator and (optionally) a user's rewards.
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            _rewards[account] = earned(account);
            _userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
}

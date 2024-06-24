// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

interface IStakingRewards {
    /* ========== VIEWS ========== */

    function balanceOf(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function rewardsDistribution() external view returns (address);

    function rewardsToken() external view returns (address);

    function totalSupply() external view returns (uint256);

    function owner() external view returns (address);

    function stakingToken() external view returns (address);

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external;

    function stakeFor(address user, uint256 amount) external;

    function getReward() external;

    function withdraw(uint256 amount) external;

    function withdrawFor(address user, uint256 amount, bool exit) external;

    function exit() external;

    function cloneStakingPool(
        address _owner,
        address _stakingToken,
        address _zapContract
    ) external returns (address newStakingPool);
}

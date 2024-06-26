// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

interface IStakingRewards {
    /* ========== VIEWS ========== */

    function balanceOf(address _account) external view returns (uint256);

    function earned(address _account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function rewardsDistribution() external view returns (address);

    function rewardsToken() external view returns (address);

    function totalSupply() external view returns (uint256);

    function owner() external view returns (address);

    function stakingToken() external view returns (address);

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 _amount) external;

    function stakeFor(address _user, uint256 _amount) external;

    function getReward() external;

    function withdraw(uint256 _amount) external;

    function withdrawFor(address _user, uint256 _amount, bool _exit) external;

    function exit() external;

    function cloneStakingPool(
        address _owner,
        address _stakingToken,
        address _zapContract
    ) external returns (address newStakingPool);
}

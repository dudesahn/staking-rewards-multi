// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console2.sol";
import {Setup, IERC20, StakingRewardsMulti} from "./utils/Setup.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_operation_basic() public {
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        uint256 amountToStake = mintVaultToken(user, amount);
        assertGt(stakingToken.balanceOf(user), 0);

        // stake our assets
        vm.startPrank(user);
        vm.expectRevert("Must be >0");
        stakingPool.stake(0);
        stakingToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.stake(amountToStake);
        vm.stopPrank();
        uint256 underlyingBalance = stakingPool.balanceOfUnderlying(user);
        assertEq(stakingPool.balanceOf(user), amountToStake);
        assertGt(underlyingBalance, amountToStake);
        console2.log("Balance of underlying DAI:%e", underlyingBalance);

        // airdrop some token to use for rewards
        airdrop(rewardToken, management, 10e18);
        vm.startPrank(management);

        // will revert if we haven't added it first
        vm.expectRevert("!authorized");
        stakingPool.notifyRewardAmount(address(rewardToken), 1e18);

        // add token to rewards array
        stakingPool.addReward(address(rewardToken), management, WEEK);
        rewardToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken), 1e18);
        vm.stopPrank();

        // only owner can setup rewards
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        stakingPool.addReward(address(rewardToken), management, WEEK);

        // check how much rewards we have for the week
        uint256 firstWeekRewards = stakingPool.getRewardForDuration(
            address(rewardToken)
        );
        assertGt(firstWeekRewards, 0);
        console2.log("Total Rewards per week (starting):%e", firstWeekRewards);

        // sleep to earn some profits
        skip(86400);

        // check earnings, get reward
        uint256 earned = stakingPool.earned(user, address(rewardToken));
        assertGt(earned, 0);
        console2.log("User Rewards earned after 24 hours:%e", earned);
        vm.prank(user);
        stakingPool.getReward();
        assertGe(rewardToken.balanceOf(user), earned);
        uint256 currentProfits = rewardToken.balanceOf(user);

        // can't withdraw zero
        vm.startPrank(user);
        vm.expectRevert("Must be >0");
        stakingPool.withdraw(0);

        // user withdraws ~half of their assets
        stakingPool.withdraw(amount / 2);

        // sleep to earn some profits
        skip(86400);

        // user fully exits
        stakingPool.exit();
        uint256 totalGains = rewardToken.balanceOf(user);
        assertGt(totalGains, currentProfits);
        console2.log("User Rewards earned after 48 hours:%e", totalGains);
        assertEq(stakingPool.balanceOf(user), 0);
    }

    function test_cloning() public {
        // shouldn't be able to initialize again our template pool
        vm.startPrank(management);
        vm.expectRevert("already initialized");
        stakingPool.initialize(management, address(stakingToken), address(zap));

        // clone a new staking pool
        StakingRewardsMulti clonedPool = StakingRewardsMulti(
            stakingPool.cloneStakingPool(
                management,
                address(stakingToken),
                address(zap)
            )
        );
        vm.expectRevert("already initialized");
        clonedPool.initialize(management, address(stakingToken), address(zap));

        vm.expectRevert("clone");
        clonedPool.cloneStakingPool(
            management,
            address(stakingToken),
            address(zap)
        );
        vm.stopPrank();

        // check that owner is what we expect
        assertEq(clonedPool.owner(), management);
        assertEq(clonedPool.pendingOwner(), address(0));

        // ** Run through our basic operation test on the cloned pool, should function the exact same
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        uint256 amountToStake = mintVaultToken(user, amount);
        assertGt(stakingToken.balanceOf(user), 0);

        // stake our assets
        vm.startPrank(user);
        vm.expectRevert("Must be >0");
        clonedPool.stake(0);
        stakingToken.approve(address(clonedPool), type(uint256).max);
        clonedPool.stake(amountToStake);
        vm.stopPrank();
        assertEq(clonedPool.balanceOf(user), amountToStake);

        // airdrop some token to use for rewards
        airdrop(rewardToken, management, 10e18);
        vm.startPrank(management);

        // will revert if we haven't added it first
        vm.expectRevert("!authorized");
        clonedPool.notifyRewardAmount(address(rewardToken), 1e18);

        // add token to rewards array
        clonedPool.addReward(address(rewardToken), management, WEEK);
        rewardToken.approve(address(clonedPool), type(uint256).max);
        clonedPool.notifyRewardAmount(address(rewardToken), 1e18);
        vm.stopPrank();

        // only owner can setup rewards
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        clonedPool.addReward(address(rewardToken), management, WEEK);

        // check how much rewards we have for the week
        uint256 firstWeekRewards = clonedPool.getRewardForDuration(
            address(rewardToken)
        );
        assertGt(firstWeekRewards, 0);
        console2.log("Total Rewards per week (starting):%e", firstWeekRewards);

        // sleep to earn some profits
        skip(86400);

        // check earnings, get reward
        uint256 earned = clonedPool.earned(user, address(rewardToken));
        assertGt(earned, 0);
        console2.log("User Rewards earned after 24 hours:%e", earned);
        vm.prank(user);
        clonedPool.getReward();
        assertGe(rewardToken.balanceOf(user), earned);
        uint256 currentProfits = rewardToken.balanceOf(user);

        // can't withdraw zero
        vm.startPrank(user);
        vm.expectRevert("Must be >0");
        clonedPool.withdraw(0);

        // user withdraws ~half of their assets
        clonedPool.withdraw(amount / 2);

        // sleep to earn some profits
        skip(86400);

        // user fully exits
        clonedPool.exit();
        uint256 totalGains = rewardToken.balanceOf(user);
        assertGt(totalGains, currentProfits);
        console2.log("User Rewards earned after 48 hours:%e", totalGains);
        assertEq(clonedPool.balanceOf(user), 0);
    }

    function test_multiple_rewards() public {
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        uint256 amountToStake = mintVaultToken(user, amount);
        assertGt(stakingToken.balanceOf(user), 0);

        // stake our assets
        vm.startPrank(user);
        vm.expectRevert("Must be >0");
        stakingPool.stake(0);
        stakingToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.stake(amountToStake);
        vm.stopPrank();
        assertEq(stakingPool.balanceOf(user), amountToStake);

        // airdrop some token to use for rewards
        airdrop(rewardToken, management, 10e18);
        airdrop(rewardToken2, management, 1_000e18);
        vm.startPrank(management);

        // add token to rewards array
        stakingPool.addReward(address(rewardToken), management, WEEK);
        rewardToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken), 1e18);

        // can't add the same token
        vm.expectRevert("Reward already added");
        stakingPool.addReward(address(rewardToken), management, WEEK);

        // can't adjust duration while we're in progress
        vm.expectRevert("Rewards active");
        stakingPool.setRewardsDuration(address(rewardToken), WEEK);

        // can't add zero address
        vm.expectRevert("No zero address");
        stakingPool.addReward(address(rewardToken), address(0), WEEK);
        vm.expectRevert("No zero address");
        stakingPool.addReward(address(0), management, WEEK);

        // add second token
        // duration must be >0
        vm.expectRevert("Must be >0");
        stakingPool.addReward(address(rewardToken2), management, 0);
        stakingPool.addReward(address(rewardToken2), management, WEEK);
        rewardToken2.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken2), 100e18);
        vm.stopPrank();

        // check reward token length
        uint256 length = stakingPool.rewardTokensLength();
        assertEq(length, 2);

        // check how much rewards we have for the week
        uint256 firstWeekRewards = stakingPool.getRewardForDuration(
            address(rewardToken)
        );
        uint256 firstWeekRewards2 = stakingPool.getRewardForDuration(
            address(rewardToken2)
        );
        assertGt(firstWeekRewards, 0);
        assertGt(firstWeekRewards2, 0);

        // sleep to earn some profits
        skip(86400);

        // check earnings
        uint256 earned = stakingPool.earned(user, address(rewardToken));
        assertGt(earned, 0);
        uint256 earnedTwo = stakingPool.earned(user, address(rewardToken2));
        assertGt(earnedTwo, 0);

        uint256[] memory earnedAmounts = new uint256[](2);
        earnedAmounts = stakingPool.earnedMulti(user);
        assertEq(earned, earnedAmounts[0]);
        assertEq(earnedTwo, earnedAmounts[1]);

        // user gets reward, withdraws
        vm.startPrank(user);
        stakingPool.getReward();
        assertGe(rewardToken.balanceOf(user), earned);
        assertGe(rewardToken2.balanceOf(user), earnedTwo);
        uint256 currentProfitsTwo = rewardToken2.balanceOf(user);

        // user withdraws ~half of their assets
        stakingPool.withdraw(amount / 2);

        // sleep to earn some profits
        skip(86400);

        // user fully exits
        stakingPool.withdraw(type(uint256).max);
        stakingPool.getReward();
        uint256 totalGainsTwo = rewardToken2.balanceOf(user);
        assertGt(totalGainsTwo, currentProfitsTwo);
        assertEq(stakingPool.balanceOf(user), 0);
        vm.stopPrank();
    }

    function test_extend_rewards() public {
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        uint256 amountToStake = mintVaultToken(user, amount);
        assertGt(stakingToken.balanceOf(user), 0);

        // stake our assets
        vm.startPrank(user);
        stakingToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.stake(amountToStake);
        vm.stopPrank();
        assertEq(stakingPool.balanceOf(user), amountToStake);

        // airdrop some token to use for rewards
        airdrop(rewardToken, management, 10e18);
        airdrop(rewardToken2, management, 1_000e18);
        vm.startPrank(management);

        // add token to rewards array
        stakingPool.addReward(address(rewardToken), management, WEEK);
        rewardToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken), 1e18);

        // add second token
        stakingPool.addReward(address(rewardToken2), management, WEEK);
        rewardToken2.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken2), 100e18);
        vm.stopPrank();

        // check reward token length
        uint256 length = stakingPool.rewardTokensLength();
        assertEq(length, 2);

        // check how much rewards we have for the week
        uint256 firstWeekRewards = stakingPool.getRewardForDuration(
            address(rewardToken)
        );
        uint256 firstWeekRewards2 = stakingPool.getRewardForDuration(
            address(rewardToken2)
        );
        assertGt(firstWeekRewards, 0);
        assertGt(firstWeekRewards2, 0);

        // sleep to earn some profits
        skip(86400);

        // check earnings
        uint256 earned = stakingPool.earned(user, address(rewardToken));
        assertGt(earned, 0);
        uint256 earnedTwo = stakingPool.earned(user, address(rewardToken2));
        assertGt(earnedTwo, 0);

        uint256[] memory earnedAmounts = new uint256[](2);
        earnedAmounts = stakingPool.earnedMulti(user);
        assertEq(earned, earnedAmounts[0]);
        assertEq(earnedTwo, earnedAmounts[1]);

        // user gets reward, withdraws
        vm.prank(user);
        stakingPool.getReward();
        assertGe(rewardToken.balanceOf(user), earned);
        assertGe(rewardToken2.balanceOf(user), earnedTwo);
        uint256 currentProfitsTwo = rewardToken2.balanceOf(user);

        // add some more rewards
        vm.prank(management);
        stakingPool.notifyRewardAmount(address(rewardToken), 1e18);
        uint256 firstWeekRewardsCheckTwo = stakingPool.getRewardForDuration(
            address(rewardToken)
        );
        uint256 firstWeekRewards2CheckTwo = stakingPool.getRewardForDuration(
            address(rewardToken2)
        );
        assertEq(firstWeekRewards2, firstWeekRewards2CheckTwo);
        assertGt(firstWeekRewardsCheckTwo, firstWeekRewards);

        // TODO: ADD MORE TESTING HERE
    }

    function test_retire() public {
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        uint256 amountToStake = mintVaultToken(user, amount);
        assertGt(stakingToken.balanceOf(user), 0);
        assertEq(stakingPool.totalSupply(), 0);

        // stake our assets
        vm.startPrank(user);
        vm.expectRevert("Must be >0");
        stakingPool.stake(0);
        stakingToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.stake(amountToStake);
        vm.stopPrank();
        assertEq(stakingPool.balanceOf(user), amountToStake);
        assertGt(stakingPool.totalSupply(), 0);

        // airdrop some token to use for rewards
        airdrop(rewardToken, management, 10e18);
        airdrop(rewardToken2, management, 1_000e18);
        vm.startPrank(management);

        // should be zero before adding
        assertEq(stakingPool.getRewardForDuration(address(rewardToken2)), 0);
        assertEq(stakingPool.getRewardForDuration(address(rewardToken)), 0);

        // add token to rewards array
        stakingPool.addReward(address(rewardToken), management, WEEK);
        rewardToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken), 1e18);
        stakingPool.addReward(address(rewardToken2), management, WEEK);
        rewardToken2.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken2), 100e18);
        vm.stopPrank();

        // sleep to earn some profits
        skip(86400);

        // check earnings
        uint256 earned = stakingPool.earned(user, address(rewardToken));
        assertGt(earned, 0);
        uint256 earnedTwo = stakingPool.earned(user, address(rewardToken2));
        assertGt(earnedTwo, 0);

        uint256[] memory earnedAmounts = new uint256[](2);
        earnedAmounts = stakingPool.earnedMulti(user);
        assertEq(earned, earnedAmounts[0]);
        assertEq(earnedTwo, earnedAmounts[1]);

        // user gets reward
        vm.startPrank(user);
        stakingPool.getReward();
        assertGe(rewardToken.balanceOf(user), earned);
        assertGe(rewardToken2.balanceOf(user), earnedTwo);
        uint256 currentProfitsTwo = rewardToken2.balanceOf(user);

        // user withdraws ~half of their assets
        stakingPool.withdraw(amount / 2);

        // sleep to earn some profits
        skip(86400);

        // user fully exits, claim rewards one at a time
        stakingPool.withdraw(type(uint256).max);
        stakingPool.getOneReward(address(rewardToken));
        stakingPool.getOneReward(address(rewardToken2));
        uint256 totalGainsTwo = rewardToken2.balanceOf(user);
        assertGt(totalGainsTwo, currentProfitsTwo);
        assertEq(stakingPool.balanceOf(user), 0);
        vm.stopPrank();

        // check how much rewards is left in the contract
        uint256 yfiLeft = rewardToken.balanceOf(address(stakingPool));
        uint256 linkLeft = rewardToken2.balanceOf(address(stakingPool));

        // sleep so that our rewards run out
        skip(86400 * 10);

        // user deposits again
        vm.prank(user);
        stakingPool.stake(amountToStake);

        // sleep so that we are 90 days past end of period
        skip(86400 * 90);

        // user shouldn't have any earned tokens
        assertEq(0, stakingPool.earned(user, address(rewardToken)));
        assertEq(0, stakingPool.earned(user, address(rewardToken2)));
        earnedAmounts = stakingPool.earnedMulti(user);
        assertEq(0, earnedAmounts[0]);
        assertEq(0, earnedAmounts[1]);

        // management sweeps out remaining rewards
        vm.startPrank(management);
        uint256 yfiBefore = rewardToken.balanceOf(management);
        stakingPool.recoverERC20(address(rewardToken), 0); // can pass whatever number we want for rewardTokens; will always be full balance
        assertEq(rewardToken.balanceOf(management), yfiBefore + yfiLeft);
        assertEq(rewardToken.balanceOf(address(stakingPool)), 0);
        uint256 linkBefore = rewardToken2.balanceOf(management);
        stakingPool.recoverERC20(address(rewardToken2), 0);
        assertEq(rewardToken2.balanceOf(management), linkBefore + linkLeft);
        assertEq(rewardToken2.balanceOf(address(stakingPool)), 0);
        vm.stopPrank();

        // earned should all be zero
        assertEq(0, stakingPool.earned(user, address(rewardToken)));
        assertEq(0, stakingPool.earned(user, address(rewardToken2)));
        earnedAmounts = stakingPool.earnedMulti(user);
        assertEq(0, earnedAmounts[0]);
        assertEq(0, earnedAmounts[1]);
        assertEq(stakingPool.balanceOf(user), amountToStake);

        // user should be able to withdraw, but can't deposit more
        vm.startPrank(user);
        vm.expectRevert("Pool retired");
        stakingPool.stake(amountToStake);

        // no problem claiming rewards, even if we don't have any
        stakingPool.getOneReward(address(rewardToken));
        stakingPool.getOneReward(address(rewardToken2));
        stakingPool.getReward();

        // withdraw half and then exit the rest
        uint256 before = stakingToken.balanceOf(user);
        assertGt(stakingPool.totalSupply(), 0);
        stakingPool.withdraw(amountToStake / 2);
        stakingPool.exit();
        assertEq(stakingPool.balanceOf(user), 0);
        assertEq(stakingToken.balanceOf(user), before + amountToStake);
        assertEq(stakingPool.totalSupply(), 0);
        vm.stopPrank();

        // should still be greater than zero
        assertGt(stakingPool.getRewardForDuration(address(rewardToken2)), 0);
        assertGt(stakingPool.getRewardForDuration(address(rewardToken)), 0);
    }
}

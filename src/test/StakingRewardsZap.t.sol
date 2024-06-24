// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console2.sol";
import {Setup, IERC20, StakingRewardsMulti} from "./utils/Setup.sol";

contract ZapOperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_zap_in() public {
        // mint a user some amount of underlying
        uint256 amount = 1_000e18;
        airdrop(underlying, user, amount);
        vm.startPrank(user);
        underlying.approve(address(zap), type(uint256).max);

        // stake our assets via zap
        vm.expectRevert("staking pool doesn't exist");
        zap.zapIn(address(stakingToken), amount);

        // can't zap in to zero address
        vm.expectRevert("staking pool doesn't exist");
        zap.zapIn(address(0), amount);

        // add staking pool to registry
        vm.expectRevert("!authorized");
        registry.addStakingPool(
            address(stakingPool),
            address(stakingToken),
            false
        );
        vm.stopPrank();
        vm.prank(management);
        registry.addStakingPool(
            address(stakingPool),
            address(stakingToken),
            false
        );
        vm.startPrank(user);

        // can't zap in zero
        vm.expectRevert("cannot mint zero");
        zap.zapIn(address(stakingToken), 0);

        // zap in, finally
        zap.zapIn(address(stakingToken), amount);
        uint256 underlyingBalance = stakingPool.balanceOfUnderlying(user);
        assertApproxEqAbs(underlyingBalance, amount, 1); // allow 1 wei of difference for rounding
        console2.log("Balance of underlying DAI:%e", underlyingBalance);
        vm.stopPrank();

        // check that zap doesn't have any underlying or stakingToken in it
        assertEq(stakingToken.balanceOf(address(zap)), 0);
        assertEq(underlying.balanceOf(address(zap)), 0);

        // make sure zap can't withdraw anything for itself
        assertEq(stakingPool.balanceOf(address(zap)), 0);
        vm.prank(address(zap));
        vm.expectRevert();
        stakingPool.withdraw(amount / 2);
        assertEq(stakingToken.balanceOf(address(zap)), 0);

        // airdrop some token to use for rewards
        airdrop(rewardToken, management, 10e18);
        airdrop(rewardToken2, management, 1_000e18);

        // add rewards to our staking contract
        vm.startPrank(management);
        stakingPool.addReward(address(rewardToken), management, WEEK);
        rewardToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken), 1e18);
        stakingPool.addReward(address(rewardToken2), management, WEEK);
        rewardToken2.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken2), 100e18);
        vm.stopPrank();

        // sleep to earn some moola
        skip(86400);

        // check user balance of rewards
        assertEq(rewardToken.balanceOf(user), 0);
        assertEq(rewardToken2.balanceOf(user), 0);

        // make sure that user is earning, not zap
        uint256 earned = stakingPool.earned(user, address(rewardToken));
        uint256 earned2 = stakingPool.earned(user, address(rewardToken2));
        assertEq(stakingPool.earned(address(zap), address(rewardToken)), 0);
        assertEq(stakingPool.earned(address(zap), address(rewardToken2)), 0);
        assertGt(earned, 0);
        assertGt(earned2, 0);

        // claim reward, make sure it all goes to user, not zap
        vm.prank(user);
        stakingPool.getReward();
        assertGe(rewardToken.balanceOf(user), earned);
        assertGe(rewardToken2.balanceOf(user), earned2);
        assertEq(rewardToken.balanceOf(address(zap)), 0);
        assertEq(rewardToken2.balanceOf(address(zap)), 0);
        earned = rewardToken.balanceOf(user);
        earned2 = rewardToken2.balanceOf(user);
        uint256 stakingBalance = stakingPool.balanceOf(user);

        // sleep to earn some moola
        skip(86400);

        // make sure user can exit with more profit and take their principal with them
        vm.prank(user);
        stakingPool.exit();
        assertEq(stakingBalance, stakingToken.balanceOf(user));
        assertGt(rewardToken.balanceOf(user), earned);
        assertGt(rewardToken2.balanceOf(user), earned2);
    }

    function test_zap_out() public {
        // mint a user some amount of underlying, have them deposit to vault token
        uint256 amount = 1_000e18;
        uint256 amountToStake = mintVaultToken(user, amount);
        assertGt(stakingToken.balanceOf(user), 0);

        // stake our assets
        vm.startPrank(user);
        stakingToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.stake(amountToStake);
        vm.stopPrank();
        uint256 underlyingBalance = stakingPool.balanceOfUnderlying(user);
        assertEq(stakingPool.balanceOf(user), amountToStake);
        assertGt(underlyingBalance, amountToStake);
        console2.log("Balance of underlying DAI:%e", underlyingBalance);

        // add staking pool to registry
        vm.prank(management);
        registry.addStakingPool(
            address(stakingPool),
            address(stakingToken),
            false
        );

        // check that zap doesn't have any underlying or stakingToken in it
        assertEq(stakingToken.balanceOf(address(zap)), 0);
        assertEq(underlying.balanceOf(address(zap)), 0);

        // make sure zap can't withdraw anything for itself
        assertEq(stakingPool.balanceOf(address(zap)), 0);
        vm.prank(address(zap));
        vm.expectRevert();
        stakingPool.withdraw(amount / 2);
        assertEq(stakingToken.balanceOf(address(zap)), 0);

        // airdrop some token to use for rewards
        airdrop(rewardToken, management, 10e18);
        airdrop(rewardToken2, management, 1_000e18);

        // add rewards to our staking contract
        vm.startPrank(management);
        stakingPool.addReward(address(rewardToken), management, WEEK);
        rewardToken.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken), 1e18);
        stakingPool.addReward(address(rewardToken2), management, WEEK);
        rewardToken2.approve(address(stakingPool), type(uint256).max);
        stakingPool.notifyRewardAmount(address(rewardToken2), 100e18);
        vm.stopPrank();

        // sleep to earn some moola
        skip(86400);

        // check user balance of rewards
        assertEq(rewardToken.balanceOf(user), 0);
        assertEq(rewardToken2.balanceOf(user), 0);

        // make sure that user is earning, not zap
        uint256 earned = stakingPool.earned(user, address(rewardToken));
        uint256 earned2 = stakingPool.earned(user, address(rewardToken2));
        assertEq(stakingPool.earned(address(zap), address(rewardToken)), 0);
        assertEq(stakingPool.earned(address(zap), address(rewardToken2)), 0);
        assertGt(earned, 0);
        assertGt(earned2, 0);

        // claim reward, make sure it all goes to user, not zap
        vm.prank(user);
        stakingPool.getReward();
        assertGe(rewardToken.balanceOf(user), earned);
        assertGe(rewardToken2.balanceOf(user), earned2);
        assertEq(rewardToken.balanceOf(address(zap)), 0);
        assertEq(rewardToken2.balanceOf(address(zap)), 0);
        earned = rewardToken.balanceOf(user);
        earned2 = rewardToken2.balanceOf(user);
        uint256 stakingBalance = stakingPool.balanceOfUnderlying(user);

        // zap out half of our funds
        vm.startPrank(user);
        vm.expectRevert("staking pool doesn't exist");
        zap.zapOut(address(0), 500e18, false);
        zap.zapOut(
            address(stakingToken),
            stakingPool.balanceOf(user) / 2,
            false
        );

        // check that zap doesn't have any underlying or stakingToken in it
        assertEq(stakingToken.balanceOf(address(zap)), 0);
        assertEq(underlying.balanceOf(address(zap)), 0);

        // sleep to earn some moola
        skip(86400);

        // only zap contract can call withdrawFor
        vm.expectRevert("!authorized");
        stakingPool.withdrawFor(user, 100e18, true);

        // if exiting, must unstake full balance
        vm.expectRevert("Must withdraw all");
        zap.zapOut(address(stakingToken), 10, true);

        // make sure user can exit (via zap) with more profit and take their principal with them
        zap.zapOut(address(stakingToken), type(uint256).max, true);
        uint256 userUnderlying = underlying.balanceOf(user);
        assertGe(userUnderlying, amount); // assume we earned some interest from yvDAI-1
        assertGe(userUnderlying, stakingBalance); // assume we earned maybe a bit of interest from yvDAI-1
        assertEq(stakingPool.balanceOf(user), 0);
        assertEq(stakingToken.balanceOf(user), 0);
        assertGt(rewardToken.balanceOf(user), earned);
        assertGt(rewardToken2.balanceOf(user), earned2);
        assertEq(rewardToken.balanceOf(address(zap)), 0);
        assertEq(rewardToken2.balanceOf(address(zap)), 0);
        assertEq(stakingToken.balanceOf(address(zap)), 0);
        assertEq(underlying.balanceOf(address(zap)), 0);
        console2.log("User final underlying balance:%e", userUnderlying);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console2.sol";
import {Setup, IERC20, StakingRewardsMulti} from "./utils/Setup.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_operation_basic() public {
        // check that dai isn't registered yet
        assertEq(registry.stakingPool(address(stakingToken)), address(0));

        // only management can add pools
        vm.prank(user);
        vm.expectRevert("!authorized");
        registry.addStakingPool(
            address(stakingPool),
            address(stakingToken),
            false
        );

        // management can add pools because they're an approved endorser
        vm.prank(management);
        registry.addStakingPool(
            address(stakingPool),
            address(stakingToken),
            false
        );
        assertNotEq(registry.stakingPool(address(stakingToken)), address(0));

        // test more shit
    }
}

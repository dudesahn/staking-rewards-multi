// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";
import {StakingRewardsMulti, IERC20} from "src/StakingRewardsMulti.sol";
import {StakingRewardsRegistry} from "src/StakingRewardsRegistry.sol";
import {StakingRewardsZap} from "src/StakingRewardsZap.sol";
import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract Setup is ExtendedTest {
    // Contract instances that we will use repeatedly.
    ERC4626 public stakingToken;
    ERC20 public underlying;
    StakingRewardsRegistry public registry;
    StakingRewardsMulti public stakingPool;
    StakingRewardsZap public zap;
    ERC20 public rewardToken;
    ERC20 public rewardToken2;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);

    // Integer variables that will be used repeatedly.
    uint256 public MAX_BPS = 10_000;
    uint256 public WEEK;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 10_000;

    function setUp() public virtual {
        _setTokenAddrs();

        WEEK = 86400 * 7;

        // Setup tokens
        stakingToken = ERC4626(tokenAddrs["yvDAI"]);
        underlying = ERC20(stakingToken.asset());
        rewardToken = ERC20(tokenAddrs["YFI"]);
        rewardToken2 = ERC20(tokenAddrs["LINK"]);

        // deploy staking pool template, registry and zap
        _deployRegistry();
        _deployZapContract();
        _deployStakingPool();

        // label all the used addresses for traces
        vm.label(user, "user");
        vm.label(management, "management");
        vm.label(address(stakingToken), "staking token");
        vm.label(address(underlying), "underlying");
    }

    function _deployRegistry() internal {
        vm.startPrank(management);
        registry = new StakingRewardsRegistry();

        // give management the power
        registry.setPoolEndorsers(address(management), true);
        registry.setApprovedPoolOwner(address(management), true);
        vm.stopPrank();
    }

    function _deployZapContract() internal {
        vm.prank(management);
        zap = new StakingRewardsZap(address(registry));
    }

    function _deployStakingPool() internal {
        vm.prank(management);
        stakingPool = new StakingRewardsMulti(
            address(management),
            address(stakingToken),
            address(zap)
        );

        // set our defaults
        vm.prank(management);
        registry.setDefaultContracts(address(stakingPool), address(zap));
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function mintVaultToken(
        address _user,
        uint256 _amount
    ) public returns (uint256 vaultTokenMinted) {
        airdrop(underlying, _user, _amount);
        vm.startPrank(_user);
        underlying.approve(address(stakingToken), _amount);
        vaultTokenMinted = stakingToken.deposit(_amount, _user);
        vm.stopPrank();
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenAddrs["yvDAI"] = 0x028eC7330ff87667b6dfb0D94b954c820195336c;
    }

    // add this to be excluded from coverage report 🚨🚨🚨 REMOVE BEFORE DEPLOYMENT LOL 🚨🚨🚨
    function test_skip_too() public {}
}

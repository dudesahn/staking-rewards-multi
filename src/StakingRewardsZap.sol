// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IStakingRewards} from "./interfaces/IStakingRewards.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";

contract StakingRewardsZap is Ownable2Step {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    /// @notice Address of our staking pool registry.
    IRegistry public stakingPoolRegistry;

    /* ========== EVENTS ========== */

    event ZapIn(
        address indexed user,
        address indexed targetVault,
        uint256 amount
    );
    event ZapOut(address indexed user, address indexed vault, uint256 amount);
    event UpdatedPoolRegistry(address registry);
    event Recovered(address token, uint256 amount);

    /* ========== CONSTRUCTOR ========== */

    constructor(address _stakingPoolRegistry) {
        stakingPoolRegistry = IRegistry(_stakingPoolRegistry);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Zap in a vault token's underlying. Deposit to the vault, stake in the staking contract for extra rewards.
     * @dev Can't stake zero. Compatible with any ERC-4626 or Legacy Yearn V2 vault.
     * @param _targetVault Vault (and thus dictates underlying token needed).
     * @param _underlyingAmount Amount of underlying tokens to deposit.
     * @param _isLegacy Whether this is a V2 Yearn vault. Generally should be false.
     * @return toStake Amount of vault tokens we ended up staking.
     */
    function zapIn(
        address _targetVault,
        uint256 _underlyingAmount,
        bool _isLegacy
    ) external returns (uint256 toStake) {
        // check what our address is, make sure it's not zero
        address _vaultStakingPool = stakingPoolRegistry.stakingPool(
            _targetVault
        );
        require(_vaultStakingPool != address(0), "staking pool doesn't exist");

        // get our underlying token
        IVault targetVault = IVault(_targetVault);
        IERC20 underlying;
        if (_isLegacy) {
            underlying = targetVault.token();
        } else {
            underlying = targetVault.asset();
        }

        // transfer to zap and deposit underlying to vault, but first check our approvals
        _checkAllowance(_targetVault, address(underlying), _underlyingAmount);

        // check our before amount in case there is any loose token stuck in the zap
        uint256 beforeAmount = underlying.balanceOf(address(this));
        underlying.safeTransferFrom(
            msg.sender,
            address(this),
            _underlyingAmount
        );

        // deposit only our underlying amount, make sure deposit worked
        toStake = targetVault.deposit(_underlyingAmount, address(this));

        // make sure we have approved the staking pool, as they can be added/updated at any time
        _checkAllowance(_vaultStakingPool, _targetVault, toStake);

        // stake for our user, return the amount we staked
        IStakingRewards(_vaultStakingPool).stakeFor(msg.sender, toStake);
        emit ZapIn(msg.sender, _targetVault, toStake);
    }

    /**
     * @notice Withdraw vault tokens from the staking pool and withdraw underlying asset.
     * @dev Can't zap out zero. Compatible with any ERC-4626 or Legacy Yearn V2 vault.
     * @param _vault Address of vault token to zap out.
     * @param _vaultTokenAmount Amount of vault tokens to zap out.
     * @param _maxLoss Maximum loss (in basis points) allowed when withdrawing.
     * @param _isLegacy Whether this is a V2 Yearn vault. Generally should be false.
     * @param _exit If true, also claim all rewards. Must be withdrawing all.
     * @return underlyingAmount Amount of underlying sent back to user.
     */
    function zapOut(
        address _vault,
        uint256 _vaultTokenAmount,
        uint256 _maxLoss,
        bool _isLegacy,
        bool _exit
    ) external returns (uint256 underlyingAmount) {
        // check what our address is, make sure it's not zero
        address _vaultStakingPool = stakingPoolRegistry.stakingPool(_vault);
        require(_vaultStakingPool != address(0), "staking pool doesn't exist");

        // sanitize input value so we can pass max_uint
        if (_vaultTokenAmount == type(uint256).max || _exit) {
            _vaultTokenAmount = IStakingRewards(_vaultStakingPool).balanceOf(
                msg.sender
            );
        }

        // withdraw from staking pool to zap
        IStakingRewards(_vaultStakingPool).withdrawFor(
            msg.sender,
            _vaultTokenAmount,
            _exit
        );

        // get our underlying token
        IVault targetVault = IVault(_vault);
        IERC20 underlying;
        if (_isLegacy) {
            underlying = targetVault.token();
        } else {
            underlying = targetVault.asset();
        }

        // check our before amount in case there is any loose token stuck in the zap
        uint256 beforeAmount = underlying.balanceOf(address(this));
        if (_isLegacy) {
            underlyingAmount = targetVault.withdraw(
                _vaultTokenAmount,
                address(this),
                _maxLoss
            );
        } else {
            underlyingAmount = targetVault.redeem(
                _vaultTokenAmount,
                address(this),
                address(this),
                _maxLoss
            );
        }

        // send underlying token to user
        underlying.safeTransfer(msg.sender, underlyingAmount);

        emit ZapOut(msg.sender, _vault, underlyingAmount);
    }

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _contract) < _amount) {
            IERC20(_token).forceApprove(_contract, type(uint256).max);
        }
    }

    /// @notice Use this in case someone accidentally sends tokens here.
    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /* ========== SETTERS ========== */

    /**
    @notice Set the registry for pulling our staking pools.
    @dev Throws if caller is not owner.
    @param _stakingPoolRegistry The address to use as pool registry.
     */
    function setPoolRegistry(address _stakingPoolRegistry) external onlyOwner {
        stakingPoolRegistry = IRegistry(_stakingPoolRegistry);
        emit UpdatedPoolRegistry(_stakingPoolRegistry);
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "@openzeppelin/contracts@4.9.3/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts@4.9.3/access/Ownable.sol";

interface IVault is IERC20 {
    // v2 vault
    function token() external view returns (address);

    // v3 vault and tokenized strategy (ERC-4626)
    function asset() external view returns (address);

    // v2 vault and v3/tokenized ERC-4626 (both the same)
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);

    // v2 vault
    function withdraw(
        uint256 maxShares,
        address recipient
    ) external returns (uint256 assets);

    // v3 vault and tokenized strategy (ERC-4626)
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);
}

interface IStakingRewards {
    function stakeFor(address recipient, uint256 amount) external;

    function withdrawFor(address recipient, uint256 amount, bool exit) external;
}

interface IRegistry {
    function stakingPool(address vault) external view returns (address);
}

contract StakingRewardsZap is Ownable {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    /// @notice Address of our staking pool registry.
    address public stakingPoolRegistry;

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
        stakingPoolRegistry = _stakingPoolRegistry;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Zap in a vault token's underlying. Deposit to the vault, stake in the staking contract for extra rewards.
     * @dev Can't stake zero. Compatible with any ERC-4626 vault.
     * @param _targetVault Vault (and thus dictates underlying token needed).
     * @param _underlyingAmount Amount of underlying tokens to deposit.
     * @return toStake Amount of vault tokens we ended up staking.
     */
    function zapIn(
        address _targetVault,
        uint256 _underlyingAmount
    ) external returns (uint256 toStake) {
        // get our staking pool from our registry for this vault token
        IRegistry poolRegistry = IRegistry(stakingPoolRegistry);

        // check what our address is, make sure it's not zero
        address _vaultStakingPool = poolRegistry.stakingPool(_targetVault);
        require(_vaultStakingPool != address(0), "staking pool doesn't exist");
        IStakingRewards vaultStakingPool = IStakingRewards(_vaultStakingPool);

        // get our underlying token
        IVault targetVault = IVault(_targetVault);
        IERC20 underlying = IERC20(targetVault.asset());

        // transfer to zap and deposit underlying to vault, but first check our approvals
        _checkAllowance(_targetVault, address(underlying), _underlyingAmount);

        // check our before amount in case there is any loose token stuck in the zap
        uint256 beforeAmount = underlying.balanceOf(address(this));
        underlying.transferFrom(msg.sender, address(this), _underlyingAmount);

        // deposit only our underlying amount, make sure deposit worked
        toStake = targetVault.deposit(_underlyingAmount, address(this));

        // this shouldn't be reached thanks to vault checks, but leave it in case vault code changes
        require(
            underlying.balanceOf(address(this)) == beforeAmount && toStake > 0,
            "deposit failed"
        );

        // make sure we have approved the staking pool, as they can be added/updated at any time
        _checkAllowance(_vaultStakingPool, _targetVault, toStake);

        // stake for our user, return the amount we staked
        vaultStakingPool.stakeFor(msg.sender, toStake);
        emit ZapIn(msg.sender, address(targetVault), toStake);
    }

    /**
     * @notice Zap in a vault token's underlying. Deposit to the vault, stake in the staking contract for extra rewards.
     * @dev Can't stake zero. For V2 (legacy) vaults only.
     * @param _targetVault Vault (and thus dictates underlying token needed).
     * @param _underlyingAmount Amount of underlying tokens to deposit.
     * @return toStake Amount of vault tokens we ended up staking.
     */
    function zapInLegacy(
        address _targetVault,
        uint256 _underlyingAmount
    ) external returns (uint256 toStake) {
        // get our staking pool from our registry for this vault token
        IRegistry poolRegistry = IRegistry(stakingPoolRegistry);

        // check what our address is, make sure it's not zero
        address _vaultStakingPool = poolRegistry.stakingPool(_targetVault);
        require(_vaultStakingPool != address(0), "staking pool doesn't exist");
        IStakingRewards vaultStakingPool = IStakingRewards(_vaultStakingPool);

        // get our underlying token
        IVault targetVault = IVault(_targetVault);
        IERC20 underlying = IERC20(targetVault.token());

        // transfer to zap and deposit underlying to vault, but first check our approvals
        _checkAllowance(_targetVault, address(underlying), _underlyingAmount);

        // check our before amount in case there is any loose token stuck in the zap
        uint256 beforeAmount = underlying.balanceOf(address(this));
        underlying.transferFrom(msg.sender, address(this), _underlyingAmount);

        // deposit only our underlying amount, make sure deposit worked
        toStake = targetVault.deposit(_underlyingAmount, address(this));

        // this shouldn't be reached thanks to vault checks, but leave it in case vault code changes
        require(
            underlying.balanceOf(address(this)) == beforeAmount && toStake > 0,
            "deposit failed"
        );

        // make sure we have approved the staking pool, as they can be added/updated at any time
        _checkAllowance(_vaultStakingPool, _targetVault, toStake);

        // stake for our user, return the amount we staked
        vaultStakingPool.stakeFor(msg.sender, toStake);
        emit ZapIn(msg.sender, address(targetVault), toStake);
    }

    /**
     * @notice Withdraw vault tokens from the staking pool and withdraw underlying asset.
     * @dev Can't zap out zero. Compatible with any ERC-4626 vault.
     * @param _vault Address of vault token to zap out.
     * @param _vaultTokenAmount Amount of vault tokens to zap out.
     * @return underlyingAmount Amount of underlying sent back to user.
     */
    function zapOut(
        address _vault,
        uint256 _vaultTokenAmount,
        bool _exit
    ) external returns (uint256 underlyingAmount) {
        // get our staking pool from our registry for this vault token
        IRegistry poolRegistry = IRegistry(stakingPoolRegistry);

        // check what our address is, make sure it's not zero
        address _vaultStakingPool = poolRegistry.stakingPool(_vault);
        require(_vaultStakingPool != address(0), "staking pool doesn't exist");
        IStakingRewards vaultStakingPool = IStakingRewards(_vaultStakingPool);

        // withdraw from staking pool to zap
        vaultStakingPool.withdrawFor(msg.sender, _vaultTokenAmount, _exit);

        // get our underlying token
        IVault targetVault = IVault(_vault);
        IERC20 underlying = IERC20(targetVault.asset());

        // check our before amount in case there is any loose token stuck in the zap
        uint256 beforeAmount = underlying.balanceOf(address(this));
        underlyingAmount = targetVault.redeem(
            _vaultTokenAmount,
            address(this),
            address(this)
        );

        // this shouldn't be reached thanks to vault checks, but leave it in case vault code changes
        require(
            underlying.balanceOf(address(this)) > beforeAmount &&
                targetVault.balanceOf(address(this)) == 0,
            "redeem failed"
        );

        // send underlying token to user
        underlying.transfer(msg.sender, underlyingAmount);

        emit ZapOut(msg.sender, _vault, underlyingAmount);
    }

    /**
     * @notice Deposit vault tokens to the staking pool.
     * @dev Can't zap out zero. For V2 (legacy) vaults only.
     * @param _vault Address of vault token to zap out.
     * @param _vaultTokenAmount Amount of vault tokens to zap out.
     * @param _exit If true, also claim all rewards. Must be withdrawing all.
     * @return underlyingAmount Amount of underlying sent back to user.
     */
    function zapOutLegacy(
        address _vault,
        uint256 _vaultTokenAmount,
        bool _exit
    ) external returns (uint256 underlyingAmount) {
        // get our staking pool from our registry for this vault token
        IRegistry poolRegistry = IRegistry(stakingPoolRegistry);

        // check what our address is, make sure it's not zero
        address _vaultStakingPool = poolRegistry.stakingPool(_vault);
        require(_vaultStakingPool != address(0), "staking pool doesn't exist");
        IStakingRewards vaultStakingPool = IStakingRewards(_vaultStakingPool);

        // withdraw from staking pool to zap
        vaultStakingPool.withdrawFor(msg.sender, _vaultTokenAmount, _exit);

        // get our underlying token
        IVault targetVault = IVault(_vault);
        IERC20 underlying = IERC20(targetVault.token());

        // check our before amount in case there is any loose token stuck in the zap
        uint256 beforeAmount = underlying.balanceOf(address(this));
        underlyingAmount = targetVault.withdraw(
            _vaultTokenAmount,
            address(this)
        );

        // this shouldn't be reached thanks to vault checks, but leave it in case vault code changes
        require(
            underlying.balanceOf(address(this)) > beforeAmount &&
                targetVault.balanceOf(address(this)) == 0,
            "withdraw failed"
        );

        // send underlying token to user
        underlying.transfer(msg.sender, underlyingAmount);

        emit ZapOut(msg.sender, _vault, underlyingAmount);
    }

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _contract) < _amount) {
            IERC20(_token).safeApprove(_contract, 0);
            IERC20(_token).safeApprove(_contract, type(uint256).max);
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
        stakingPoolRegistry = _stakingPoolRegistry;
        emit UpdatedPoolRegistry(_stakingPoolRegistry);
    }
}

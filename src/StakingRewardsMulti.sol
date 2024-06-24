// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/**
 * @title Yearn Vault Staking MultiRewards
 * @author YearnFi
 * @notice Modified staking contract that allows users to deposit vault tokens and receive multiple different reward
 *  tokens, and also allows depositing straight from vault underlying via the StakingRewardsZap. Only the owner
 *  role may add new reward tokens, or update rewardDistributor role of existing reward tokens.
 *
 *  This work builds on that of Synthetix (StakingRewards.sol) and CurveFi (MultiRewards.sol).
 *  Synthetix info: https://docs.synthetix.io/contracts/source/contracts/stakingrewards
 *  Curve MultiRewards: https://github.com/curvefi/multi-rewards/blob/master/contracts/MultiRewards.sol
 */

contract StakingRewardsMulti is ReentrancyGuard, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    struct Reward {
        /// @notice The only address able to top up rewards for a token (aka notifyRewardAmount()).
        address rewardsDistributor;
        /// @notice The duration of our rewards distribution for staking, default is 7 days.
        uint256 rewardsDuration;
        /// @notice The end (timestamp) of our current or most recent reward period.
        uint256 periodFinish;
        /// @notice The distribution rate of reward token per second.
        uint256 rewardRate;
        /**
         * @notice The last time rewards were updated, triggered by updateReward() or notifyRewardAmount().
         * @dev  Will be the timestamp of the update or the end of the period, whichever is earlier.
         */
        uint256 lastUpdateTime;
        /**
         * @notice The most recent stored amount for rewardPerToken().
         * @dev Updated every time anyone calls the updateReward() modifier.
         */
        uint256 rewardPerTokenStored;
    }

    /**
     * @notice Bool for if this staking contract is shut down and remaining rewards have been swept out.
     * @dev Reward sweep can only be performed at least 90 days after final reward period ends.
     */
    bool public isRetired;

    /// @notice Will only be true on the original deployed contract and not on clones; we don't want to clone a clone.
    bool public isOriginal = true;

    /// @notice The address of our staking token.
    IERC20 public stakingToken;

    /// @notice Array containing the addresses of all of our reward tokens.
    address[] public rewardTokens;

    /// @notice Zap contract can execute arbitrary logic before stake and after withdraw for our stakingToken.
    address public zapContract;

    /// @notice The address of our reward token => reward info.
    mapping(address => Reward) public rewardData;

    /**
     * @notice The amount of rewards allocated to a user per whole token staked.
     * @dev Note that this is not the same as amount of rewards claimed. Mapping order is user -> reward token -> amount
     */
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;

    /**
     * @notice The amount of unclaimed rewards an account is owed.
     * @dev Mapping order is user -> reward token -> amount
     */
    mapping(address => mapping(address => uint256)) public rewards;

    /// @notice Used to track the deployed version of this contract.
    string public constant stakerVersion = "1.1.0";

    // private vars, use view functions to see these
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    uint256 internal constant PRECISION = 1e18;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _owner, address _stakingToken, address _zapContract) {
        _initializePool(_owner, _stakingToken, _zapContract);
    }

    /* ========== CLONING ========== */

    /**
     * @notice Use this to clone an exact copy of this staking pool.
     * @param _owner Owner of the new staking contract.
     * @param _stakingToken Address of our staking token.
     * @param _zapContract Address of our zap contract.
     * @return newStakingPool Address of our new staking pool.
     */
    function cloneStakingPool(
        address _owner,
        address _stakingToken,
        address _zapContract
    ) external returns (address newStakingPool) {
        // don't clone a clone
        if (!isOriginal) {
            revert("clone");
        }

        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        bytes20 addressBytes = bytes20(address(this));
        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(
                clone_code,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(
                add(clone_code, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            newStakingPool := create(0, clone_code, 0x37)
        }

        StakingRewardsMulti(newStakingPool).initialize(
            _owner,
            _stakingToken,
            _zapContract
        );

        emit Cloned(newStakingPool);
    }

    /**
     * @notice Initialize the staking pool.
     * @dev This should only be called by the clone function above.
     * @param _owner Owner of the new staking contract.
     * @param _stakingToken Address of our staking token.
     * @param _zapContract Address of our zap contract.
     */
    function initialize(
        address _owner,
        address _stakingToken,
        address _zapContract
    ) public {
        _initializePool(_owner, _stakingToken, _zapContract);
    }

    // this is called by our original staking pool, as well as any clones via the above function
    function _initializePool(
        address _owner,
        address _stakingToken,
        address _zapContract
    ) internal {
        // make sure that we haven't initialized this before
        if (address(stakingToken) != address(0)) {
            revert("already initialized"); // already initialized.
        }

        // set up our state vars
        stakingToken = IERC20(_stakingToken);
        zapContract = _zapContract;
        _transferOwnership(_owner);
    }

    /* ========== VIEWS ========== */

    /// @notice The total tokens staked in this contract.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice The balance a given user has staked.
     * @param _account Address to check staked balance.
     * @return Staked balance of given user.
     */
    function balanceOf(address _account) external view returns (uint256) {
        return _balances[_account];
    }

    /**
     * @notice The balance a given user has staked, converted to underlying.
     * @dev Note this assumes that stakingToken is an ERC4626 token.
     * @param _account Address to check staked balance of underlying.
     * @return Staked underlying balance of given user.
     */
    function balanceOfUnderlying(
        address _account
    ) external view returns (uint256) {
        return
            IERC4626(address(stakingToken)).convertToAssets(
                _balances[_account]
            );
    }

    /// @notice How many reward tokens we currently have.
    function rewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    /**
     * @notice Either the current timestamp or end of the most recent period.
     * @param _rewardsToken Reward token to check.
     * @return Timestamp of last time reward applicable for token.
     */
    function lastTimeRewardApplicable(
        address _rewardsToken
    ) public view returns (uint256) {
        return
            FixedPointMathLib.min(
                block.timestamp,
                rewardData[_rewardsToken].periodFinish
            );
    }

    /**
     * @notice Reward paid out per whole token.
     * @param _rewardsToken Reward token to check.
     * @return rewardAmount Reward paid out per whole token.
     */
    function rewardPerToken(
        address _rewardsToken
    ) public view returns (uint256 rewardAmount) {
        if (_totalSupply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }

        if (isRetired) {
            return 0;
        }

        rewardAmount =
            rewardData[_rewardsToken].rewardPerTokenStored +
            (((lastTimeRewardApplicable(_rewardsToken) -
                rewardData[_rewardsToken].lastUpdateTime) *
                rewardData[_rewardsToken].rewardRate *
                PRECISION) / _totalSupply);
    }

    /**
     * @notice Amount of reward token pending claim by an account.
     * @param _account Account to check earned balance for.
     * @param _rewardsToken Rewards token to check.
     * @return pending Amount of reward token pending claim.
     */
    function earned(
        address _account,
        address _rewardsToken
    ) public view returns (uint256 pending) {
        if (isRetired) {
            return 0;
        }

        pending =
            (_balances[_account] *
                (rewardPerToken(_rewardsToken) -
                    userRewardPerTokenPaid[_account][_rewardsToken])) /
            PRECISION +
            rewards[_account][_rewardsToken];
    }

    /**
     * @notice Amount of reward token(s) pending claim by an account.
     * @dev Checks for all rewardTokens.
     * @param _account Account to check earned balance for.
     * @return pending Amount of reward token(s) pending claim.
     */
    function earnedMulti(
        address _account
    ) public view returns (uint256[] memory pending) {
        address[] memory _rewardTokens = rewardTokens;
        uint256 length = _rewardTokens.length;
        pending = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            pending[i] = earned(_account, _rewardTokens[i]);
        }
    }

    /**
     * @notice Total reward that will be paid out over the reward duration.
     * @dev These values are only updated when notifying, adding, or adjust duration of rewards.
     * @param _rewardsToken Reward token to check.
     * @return Total reward token remaining to be paid out.
     */
    function getRewardForDuration(
        address _rewardsToken
    ) external view returns (uint256) {
        return
            rewardData[_rewardsToken].rewardRate *
            rewardData[_rewardsToken].rewardsDuration;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Deposit vault tokens to the staking pool.
     * @dev Can't stake zero.
     * @param _amount Amount of vault tokens to deposit.
     */
    function stake(
        uint256 _amount
    ) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(_amount > 0, "Must be >0");
        require(!isRetired, "Pool retired");

        // add amount to total supply and user balance
        _totalSupply += _amount;
        _balances[msg.sender] += _amount;

        // stake the amount, emit the event
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    /**
     * @notice Deposit vault tokens for specified recipient.
     * @dev Can't stake zero.
     * @param _recipient Address of user these vault tokens are being staked for.
     * @param _amount Amount of vault token to deposit.
     */
    function stakeFor(
        address _recipient,
        uint256 _amount
    ) external nonReentrant whenNotPaused updateReward(_recipient) {
        require(_amount > 0, "Must be >0");
        require(!isRetired, "Pool retired");

        // add amount to total supply and user balance
        _totalSupply += _amount;
        _balances[_recipient] += _amount;

        // stake the amount, emit the event
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit StakedFor(_recipient, _amount);
    }

    /**
     * @notice Withdraw vault tokens from the staking pool.
     * @dev Can't withdraw zero. If trying to claim, call getReward() instead.
     * @param _amount Amount of vault tokens to withdraw.
     */
    function withdraw(
        uint256 _amount
    ) public nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "Must be >0");

        // sanitize input value so we can pass max_uint
        if (_amount == type(uint256).max) {
            _amount = _balances[msg.sender];
        }

        // remove amount from total supply and user balance
        _totalSupply -= _amount;
        _balances[msg.sender] -= _amount;

        // send the requested amount, emit the event
        stakingToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @notice Withdraw vault tokens from the staking pool for a specified user.
     * @dev Can't withdraw zero. May only be called by zap contract.
     * @param _recipient Address of user these vault tokens are being withdrawn for.
     * @param _amount Amount of vault tokens to withdraw.
     * @param _exit If true, withdraw all and claim all rewards
     */
    function withdrawFor(
        address _recipient,
        uint256 _amount,
        bool _exit
    ) external nonReentrant updateReward(_recipient) {
        require(msg.sender == zapContract, "!authorized");
        require(_amount > 0, "Must be >0");

        // remove amount from total supply and user balance
        _totalSupply -= _amount;
        _balances[_recipient] -= _amount;

        // send the requested amount (to the zap contract!), emit the event
        stakingToken.safeTransfer(msg.sender, _amount);
        emit WithdrawnFor(_recipient, _amount);

        // claim rewards if exiting
        if (_exit) {
            require(_balances[_recipient] == 0, "Must withdraw all");
            _getRewardFor(_recipient);
        }
    }

    /**
     * @notice Claim any (and all) earned reward tokens.
     * @dev Can claim rewards even if no tokens still staked.
     */
    function getReward() external nonReentrant updateReward(msg.sender) {
        _getRewardFor(msg.sender);
    }

    // internal function to get rewards.
    function _getRewardFor(address _recipient) internal {
        for (uint256 i; i < rewardTokens.length; ++i) {
            address _rewardsToken = rewardTokens[i];
            uint256 reward = rewards[_recipient][_rewardsToken];
            if (reward > 0) {
                rewards[_recipient][_rewardsToken] = 0;
                IERC20(_rewardsToken).safeTransfer(_recipient, reward);
                emit RewardPaid(_recipient, _rewardsToken, reward);
            }
        }
    }

    /**
     * @notice Claim any one earned reward token.
     * @dev Can claim rewards even if no tokens still staked.
     * @param _rewardsToken Address of the rewards token to claim.
     */
    function getOneReward(
        address _rewardsToken
    ) external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender][_rewardsToken];
        if (reward > 0) {
            rewards[msg.sender][_rewardsToken] = 0;
            IERC20(_rewardsToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, _rewardsToken, reward);
        }
    }

    /**
     * @notice Unstake all of the sender's tokens and claim any outstanding rewards.
     */
    function exit() external {
        withdraw(_balances[msg.sender]);
        _getRewardFor(msg.sender);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Notify staking contract that it has more reward to account for.
     * @dev May only be called by rewards distribution role. Set up token first via addReward().
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardAmount Amount of reward tokens to add.
     */
    function notifyRewardAmount(
        address _rewardsToken,
        uint256 _rewardAmount
    ) external updateReward(address(0)) {
        Reward memory _rewardData = rewardData[_rewardsToken];
        require(_rewardData.rewardsDistributor == msg.sender, "!authorized");
        require(_rewardAmount > 0, "Must be >0");

        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the reward amount
        IERC20(_rewardsToken).safeTransferFrom(
            msg.sender,
            address(this),
            _rewardAmount
        );

        if (block.timestamp >= _rewardData.periodFinish) {
            rewardData[_rewardsToken].rewardRate =
                _rewardAmount /
                _rewardData.rewardsDuration;
        } else {
            rewardData[_rewardsToken].rewardRate =
                (_rewardAmount +
                    (_rewardData.periodFinish - block.timestamp) *
                    _rewardData.rewardRate) /
                _rewardData.rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        require(
            rewardData[_rewardsToken].rewardRate <=
                (IERC20(_rewardsToken).balanceOf(address(this)) /
                    _rewardData.rewardsDuration),
            "Provided reward too high"
        );

        rewardData[_rewardsToken].lastUpdateTime = block.timestamp;
        rewardData[_rewardsToken].periodFinish =
            block.timestamp +
            _rewardData.rewardsDuration;
        emit RewardAdded(_rewardsToken, _rewardAmount);
    }

    /**
     * @notice Add a new reward token to the staking contract.
     * @dev May only be called by owner, and can't be set to zero address. Add reward tokens sparingly, as each new one
     *  will increase gas costs. This must be set before notifyRewardAmount can be used.
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardsDistributor Address of the rewards distributor.
     * @param _rewardsDuration The duration of our rewards distribution for staking in seconds.
     */
    function addReward(
        address _rewardsToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) external onlyOwner {
        require(
            _rewardsToken != address(0) && _rewardsDistributor != address(0),
            "No zero address"
        );
        require(_rewardsDuration > 0, "Must be >0");
        require(
            rewardData[_rewardsToken].rewardsDuration == 0,
            "Reward already added"
        );

        rewardTokens.push(_rewardsToken);
        rewardData[_rewardsToken].rewardsDistributor = _rewardsDistributor;
        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;
    }

    /**
     * @notice Set rewards distributor address for a given reward token.
     * @dev May only be called by owner, and can't be set to zero address.
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardsDistributor Address of the rewards distributor. This is the only address that can add new rewards
     *  for this token.
     */
    function setRewardsDistributor(
        address _rewardsToken,
        address _rewardsDistributor
    ) external onlyOwner {
        require(
            _rewardsToken != address(0) && _rewardsDistributor != address(0),
            "No zero address"
        );
        rewardData[_rewardsToken].rewardsDistributor = _rewardsDistributor;
    }

    /**
     * @notice Set the duration of our rewards period.
     * @dev May only be called by rewards distributor, and must be done after most recent period ends.
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardsDuration New length of period in seconds.
     */
    function setRewardsDuration(
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external {
        Reward memory _rewardData = rewardData[_rewardsToken];
        require(block.timestamp > _rewardData.periodFinish, "Rewards active");
        require(_rewardData.rewardsDistributor == msg.sender, "!authorized");
        require(_rewardsDuration > 0, "Must be >0");

        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;

        emit RewardsDurationUpdated(_rewardsToken, _rewardsDuration);
    }

    /**
     * @notice Set our zap contract.
     * @dev May only be called by owner, and can't be set to zero address.
     * @param _zapContract Address of the new zap contract.
     */
    function setZapContract(address _zapContract) external onlyOwner {
        require(_zapContract != address(0), "No zero address");
        zapContract = _zapContract;
        emit ZapContractUpdated(_zapContract);
    }

    /**
     * @notice Sweep out tokens accidentally sent here.
     * @dev May only be called by owner. If a pool has multiple rewards tokens to sweep out, call this once for each.
     * @param _tokenAddress Address of token to sweep.
     * @param _tokenAmount Amount of tokens to sweep.
     */
    function recoverERC20(
        address _tokenAddress,
        uint256 _tokenAmount
    ) external onlyOwner {
        if (_tokenAddress == address(stakingToken)) revert("!staking token");

        // can only recover reward tokens 90 days after last reward token ends
        bool isRewardToken;
        address[] memory _rewardTokens = rewardTokens;
        uint256 maxPeriodFinish;

        for (uint256 i; i < _rewardTokens.length; ++i) {
            uint256 rewardPeriodFinish = rewardData[_rewardTokens[i]]
                .periodFinish;
            if (rewardPeriodFinish > maxPeriodFinish) {
                maxPeriodFinish = rewardPeriodFinish;
            }

            if (_rewardTokens[i] == _tokenAddress) {
                isRewardToken = true;
            }
        }

        if (isRewardToken) {
            require(
                block.timestamp > maxPeriodFinish + 90 days,
                "wait >90 days"
            );

            // if we do this, automatically sweep all reward token
            _tokenAmount = IERC20(_tokenAddress).balanceOf(address(this));

            // retire this staking contract, this wipes all rewards but still allows all users to withdraw
            isRetired = true;
        }

        IERC20(_tokenAddress).safeTransfer(owner(), _tokenAmount);
        emit Recovered(_tokenAddress, _tokenAmount);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address _account) {
        for (uint256 i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            rewardData[token].rewardPerTokenStored = rewardPerToken(token);
            rewardData[token].lastUpdateTime = lastTimeRewardApplicable(token);
            if (_account != address(0)) {
                rewards[_account][token] = earned(_account, token);
                userRewardPerTokenPaid[_account][token] = rewardData[token]
                    .rewardPerTokenStored;
            }
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(address indexed rewardToken, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event StakedFor(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event WithdrawnFor(address indexed user, uint256 amount);
    event RewardPaid(
        address indexed user,
        address indexed rewardToken,
        uint256 reward
    );
    event RewardsDurationUpdated(address token, uint256 newDuration);
    event ZapContractUpdated(address _zapContract);
    event Recovered(address token, uint256 amount);
    event Cloned(address indexed clone);
}

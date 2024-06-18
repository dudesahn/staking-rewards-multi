// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Ownable2Step} from "@openzeppelin/contracts@4.9.3/access/Ownable2Step.sol";

interface IStakingRewards {
    function stakingToken() external view returns (address);

    function owner() external view returns (address);

    function cloneStakingPool(
        address _owner,
        address _stakingToken,
        address _zapContract
    ) external returns (address newStakingPool);
}

contract StakingRewardsRegistry is Ownable2Step {
    /* ========== STATE VARIABLES ========== */

    /// @notice If a stakingPool exists for a given token, it will be shown here.
    /// @dev Only stakingPools added to this registry will be shown.
    mapping(address => address) public stakingPool;

    /// @notice Tokens that this registry has added stakingPools for.
    address[] public tokens;

    /// @notice Check if a given stakingPool is known to this registry.
    mapping(address => bool) public isStakingPoolEndorsed;

    /// @notice Check if an address is allowed to own stakingPools from this registry.
    mapping(address => bool) public approvedPoolOwner;

    /// @notice Check if an address can add pools to this registry.
    mapping(address => bool) public poolEndorsers;

    /// @notice Staking pools that have been replaced by a newer version.
    address[] public replacedStakingPools;

    /// @notice Default StakingRewardsMulti contract to clone.
    address public stakingContract;

    /// @notice Default zap contract.
    address public zapContract;

    /* ========== EVENTS ========== */

    event StakingPoolAdded(address indexed token, address stakingPool);
    event ApprovedPoolOwnerUpdated(address governance, bool approved);
    event ApprovedPoolEndorser(address account, bool canEndorse);
    event DefaultContractsUpdated(address stakingContract, address zapContract);

    /* ========== VIEWS ========== */

    /// @notice The number of tokens with staking pools added to this registry.
    function numTokens() external view returns (uint256) {
        return tokens.length;
    }

    /* ========== CORE FUNCTIONS ========== */

    /**
     @notice Used for owner to clone an exact copy of the default staking pool and add to registry.
     @dev Also uses the default zap contract.
     @param _stakingToken Address of our staking token to use.
    */
    function cloneAndAddStakingPool(
        address _stakingToken
    ) external returns (address newStakingPool) {
        // don't let just anyone add to our registry
        require(poolEndorsers[msg.sender], "!authorized");

        // Clone new pool.
        IStakingRewards stakingRewards = IStakingRewards(stakingContract);

        newStakingPool = stakingRewards.cloneStakingPool(
            owner(),
            _stakingToken,
            zapContract
        );

        bool tokenIsRegistered = stakingPool[_stakingToken] != address(0);

        // Add to the registry.
        _addStakingPool(newStakingPool, _stakingToken, tokenIsRegistered);
    }

    /**
    @notice
        Add a new staking pool to our registry, for new or existing tokens.
    @dev
        Throws if governance isn't set properly.
        Throws if sender isn't allowed to endorse.
        Throws if replacement is handled improperly.
        Emits a StakingPoolAdded event.
    @param _stakingPool The address of the new staking pool.
    @param _token The token to be deposited into the new staking pool.
    @param _replaceExistingPool If we are replacing an existing staking pool, set this to true.
     */
    function addStakingPool(
        address _stakingPool,
        address _token,
        bool _replaceExistingPool
    ) external {
        // don't let just anyone add to our registry
        require(poolEndorsers[msg.sender], "!authorized");
        _addStakingPool(_stakingPool, _token, _replaceExistingPool);
    }

    function _addStakingPool(
        address _stakingPool,
        address _token,
        bool _replaceExistingPool
    ) internal {
        // load up the staking pool contract
        IStakingRewards stakingRewards = IStakingRewards(_stakingPool);

        // check that gov is correct on the staking contract
        address poolGov = stakingRewards.owner();
        require(approvedPoolOwner[poolGov], "not allowed pool owner");

        // make sure we didn't mess up our token/staking pool match
        require(
            stakingRewards.stakingToken() == _token,
            "staking token doesn't match"
        );

        // Make sure we're only using the latest stakingPool in our registry
        if (_replaceExistingPool) {
            require(
                stakingPool[_token] != address(0),
                "token isn't registered, can't replace"
            );
            address oldPool = stakingPool[_token];
            isStakingPoolEndorsed[oldPool] = false;
            stakingPool[_token] = _stakingPool;

            // move our old pool to the replaced list
            replacedStakingPools.push(oldPool);
        } else {
            require(
                stakingPool[_token] == address(0),
                "replace instead, pool already exists"
            );
            stakingPool[_token] = _stakingPool;
            tokens.push(_token);
        }

        isStakingPoolEndorsed[_stakingPool] = true;
        emit StakingPoolAdded(_token, _stakingPool);
    }

    /* ========== SETTERS ========== */

    /**
    @notice Set the ability of an address to endorse staking pools.
    @dev Throws if caller is not owner.
    @param _addr The address to approve or deny access.
    @param _approved Allowed to endorse
     */
    function setPoolEndorsers(
        address _addr,
        bool _approved
    ) external onlyOwner {
        poolEndorsers[_addr] = _approved;
        emit ApprovedPoolEndorser(_addr, _approved);
    }

    /**
    @notice Set the staking pool owners.
    @dev Throws if caller is not owner.
    @param _addr The address to approve or deny access.
    @param _approved Allowed to own staking pools
     */
    function setApprovedPoolOwner(
        address _addr,
        bool _approved
    ) external onlyOwner {
        approvedPoolOwner[_addr] = _approved;
        emit ApprovedPoolOwnerUpdated(_addr, _approved);
    }

    /**
    @notice Set our default zap and staking pool contracts.
    @dev Throws if caller is not owner, and can't be set to zero address.
    @param _stakingPool Address of the default staking contract to use.
    @param _zapContract Address of the default zap contract to use.
     */
    function setDefaultContracts(
        address _stakingPool,
        address _zapContract
    ) external onlyOwner {
        require(
            _stakingPool != address(0) && _zapContract != address(0),
            "no zero address"
        );
        stakingContract = _stakingPool;
        zapContract = _zapContract;
        emit DefaultContractsUpdated(_stakingPool, _zapContract);
    }
}

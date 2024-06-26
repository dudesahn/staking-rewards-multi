// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

interface IRegistry {
    function stakingPool(address vault) external view returns (address);
}

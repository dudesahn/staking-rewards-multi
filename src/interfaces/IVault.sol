// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IVault is IERC20 {
    // v2 vault
    function token() external view returns (IERC20);

    // v3 vault and tokenized strategy (ERC-4626)
    function asset() external view returns (IERC20);

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

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IVault is IERC20 {
    // v2 vault
    function token() external view returns (IERC20);

    // v3 vault and tokenized strategy (ERC-4626)
    function asset() external view returns (IERC20);

    // v2 vault and v3/tokenized ERC-4626 (both the same)
    function deposit(
        uint256 _assets,
        address _receiver
    ) external returns (uint256 shares);

    // v2 vault
    function withdraw(
        uint256 _maxShares,
        address _recipient,
        uint256 _maxLoss
    ) external returns (uint256 assets);

    // v3 vault and tokenized strategy (ERC-4626)
    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner,
        uint256 _maxLoss
    ) external returns (uint256 assets);
}

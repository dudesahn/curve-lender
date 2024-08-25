// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IYearnV2 {
    function token() external view returns (address);

    function totalAssets() external view returns (uint256);

    function depositLimit() external view returns (uint256);

    function deposit(uint256) external;

    function withdraw(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function pricePerShare() external view returns (uint256);

    function withdrawalQueue(uint256) external view returns (address);
}

interface ISharePriceHelper {
    function sharesToAmount(address, uint256) external view returns (uint256);

    function amountToShares(address, uint256) external view returns (uint256);
}

interface IGauge {
    function lp_token() external view returns (address);
}

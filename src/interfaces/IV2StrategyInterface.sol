// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

interface IV2StrategyInterface {
    function harvest() external;

    function strategist() external view returns (address);

    function withdrawalQueue(uint256) external view returns (address);

    function updateStrategyDebtRatio(address, uint256) external;
}

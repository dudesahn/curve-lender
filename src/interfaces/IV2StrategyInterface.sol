// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IV2StrategyInterface {
    function harvest() external;

    function strategist() external view returns (address);
}

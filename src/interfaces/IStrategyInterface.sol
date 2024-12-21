// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBase4626Compounder} from "@periphery/Bases/4626Compounder/IBase4626Compounder.sol";

interface IStrategyInterface is IBase4626Compounder {
    function yearnCurveLendVault() external view returns (address);
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBase4626Compounder} from "@periphery/Bases/4626Compounder/IBase4626Compounder.sol";
import {ITradeFactorySwapper} from "@periphery/swappers/interfaces/ITradeFactorySwapper.sol";

interface IStrategyInterface is IBase4626Compounder, ITradeFactorySwapper {
    function gauge() external view returns (address);

    function addToken(address) external;

    function setTradeFactory(address) external;
}

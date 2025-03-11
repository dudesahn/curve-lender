// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBase4626Compounder} from "@periphery/Bases/4626Compounder/IBase4626Compounder.sol";
import {ITradeFactorySwapper} from "@periphery/swappers/interfaces/ITradeFactorySwapper.sol";

interface IStrategyInterface is IBase4626Compounder, ITradeFactorySwapper {
    enum SwapType {
        NULL,
        TRICRV,
        AUCTION,
        TF
    }

    function gauge() external view returns (address);

    function proxy() external view returns (address);

    function addToken(address) external;

    function setTradeFactory(address) external;

    function setClaimFlags(bool, bool) external;

    function rewardsContract() external view returns (address);

    function pid() external view returns (uint256);

    // State Variables
    function auction() external view returns (address);

    function minAmountToSellMapping(address) external view returns (uint256);

    function swapType(address) external view returns (SwapType);

    function allRewardTokens(uint256) external view returns (address);

    // Functions
    function addRewardToken(address _token, SwapType _swapType) external;

    function removeRewardToken(address _token) external;

    function getAllRewardTokens() external view returns (address[] memory);

    function setAuction(address _auction) external;

    function setSwapType(address _from, SwapType _swapType) external;

    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external;

    function kickAuction(address _token) external returns (uint256);

    function setProxy(address _proxy) external;

    function setMinOutBps(uint256 _minOutBps) external;
}

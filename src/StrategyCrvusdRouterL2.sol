// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {ICurveStrategyProxy, IGauge} from "./interfaces/ICrvusdInterfaces.sol";

// *** NOTE: MAKE SURE THIS STRATEGY CAN WORK WITH MARKETS/GAUGES THAT HAVEN'T BEEN ADDED TO THE GAUGE CONTROLLER
// OR MAYBE WE JUST ALSO WRITE A STRATEGY VERSION FOR THOSE
// a bit worried this will revert somewhere in strategy proxy or something

// think about adding some testing for when markets are fully utilized? got it simulated a bit w/ wstETH, seemed fine

contract StrategyLlamaLendCurveL2 is Base4626Compounder, TradeFactorySwapper {
    using SafeERC20 for ERC20;

    // @notice Curve gauge address corresponding to our Curve Lend LP
    IGauge public immutable gauge;

    /**
     * @param _asset Underlying asset to use for this strategy.
     * @param _name Name to use for this strategy. Ideally something human readable for a UI to use.
     * @param _vault ERC4626 vault token to use. In Curve Lend, these are the base LP tokens.
     * @param _gauge Gauge address for the Curve Lend LP.
     */
    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _gauge
    ) Base4626Compounder(_asset, _name, _vault) {
        require(_vault == IGauge(_gauge).lp_token(), "gauge mismatch");
        gauge = _gauge;
    }

    /* ========== BASE4626 FUNCTIONS ========== */

    /**
     * @notice Balance of 4626 vault tokens held in our strategy proxy
     */
    function balanceOfStake() public view override returns (uint256 stake) {
        stake = gauge.balanceOf(address(this));
    }

    function _stake() internal override {
        // stake any loose 4626 vault tokens to the gauge
        gauge.deposit(balanceOfVault());
    }

    function _unStake(uint256 _amount) internal override {
        // _amount is already in 4626 vault shares, no need to convert from asset
        gauge.withdraw(_amount);
    }

    function vaultsMaxWithdraw() public view override returns (uint256) {
        // we use the gauge address here since that's where our strategy proxy deposits the LP
        // should be the minimum of what the gauge can redeem (limited by utilization), and our staked balance + loose vault tokens
        return
            vault.convertToAssets(
                Math.min(
                    vault.maxRedeem(address(gauge)),
                    balanceOfStake() + balanceOfVault()
                )
            );
    }

    /* ========== TRADE FACTORY FUNCTIONS ========== */

    function claimRewards() external override onlyManagement {
        _claimRewards();
    }

    function _claimRewards() internal override {
        // claim any extra rewards we may have
        gauge.claim_rewards();
    }

    /**
     * @notice Use to add tokens to our rewardTokens array. Also enables token on trade factory if one is set.
     * @dev Can only be called by management.
     * @param _token Address of token to add.
     */
    function addToken(address _token) external onlyManagement {
        require(
            _token != address(asset) && _token != address(vault),
            "!allowed"
        );
        _addToken(_token, address(asset));
    }

    /**
     * @notice Use to remove tokens from our rewardTokens array. Also disables token on trade factory.
     * @dev Can only be called by management.
     * @param _token Address of token to remove.
     */
    function removeToken(address _token) external onlyManagement {
        _removeToken(_token, address(asset));
    }

    /**
     * @notice Use to update our trade factory.
     * @dev Can only be called by management.
     * @param _tradeFactory Address of new trade factory.
     */
    function setTradeFactory(address _tradeFactory) external onlyManagement {
        _setTradeFactory(_tradeFactory, address(asset));
    }
}

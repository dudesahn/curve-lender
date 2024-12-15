// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {ICurveStrategyProxy, IGauge} from "./interfaces/ICrvusdInterfaces.sol";

// *** NOTE: MAKE SURE THIS STRATEGY CAN WORK WITH MARKETS/GAUGES THAT HAVEN'T BEEN ADDED TO THE GAUGE CONTROLLER
// OR MAYBE WE JUST ALSO WRITE A STRATEGY VERSION FOR THOSE
// a bit worried this will revert somewhere in strategy proxy or something

contract StrategyCrvusdRouter is Base4626Compounder, TradeFactorySwapper {
    using SafeERC20 for ERC20;

    /// @notice Yearns strategyProxy, needed for interacting with our Curve Voter.
    ICurveStrategyProxy public proxy;

    // Curve gauge address corresponding to our Curve Lend LP
    address public immutable gauge;

    // yChad, the only one who can update our strategy proxy address
    address internal constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    /**
     * @param _asset Underlying asset to use for this strategy.
     * @param _name Name to use for this strategy. Ideally something human readable for a UI to use.
     * @param _vault ERC4626 vault token to use. In Curve Lend, these are the base LP tokens.
     * @param _gauge Gauge address for the Curve Lend LP.
     * @param _proxy Address for Yearn's strategy proxy.
     */
    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _gauge,
        address _proxy
    ) Base4626Compounder(_asset, _name, _vault) {
        require(_vault == IGauge(_gauge).lp_token(), "gauge mismatch");
        gauge = _gauge;
        proxy = ICurveStrategyProxy(_proxy);
    }

    /* ========== BASE4626 FUNCTIONS ========== */

    /**
     * @notice Balance of 4626 vault tokens held in our strategy proxy
     */
    function balanceOfStake() public view override returns (uint256 stake) {
        stake = proxy.balanceOf(gauge);
    }

    function _stake() internal override {
        // send any loose 4626 vault tokens to yearn's proxy to deposit to the gauge and send to the voter
        ERC20(address(vault)).safeTransfer(address(proxy), balanceOfVault());
        proxy.deposit(gauge, address(vault));
    }

    function _unStake(uint256 _amount) internal override {
        // _amount is already in 4626 vault shares, no need to convert from asset
        // ** NOTE make sure _amount can't be more than balanceOfStake()
        require(_amount < balanceOfStake(), "!conversion");
        proxy.withdraw(gauge, address(vault), _amount);
    }

    function vaultsMaxWithdraw() public view override returns (uint256) {
        // we use the gauge address here since that's where our strategy proxy deposits the LP
        // should be the minimum of what the gauge can redeem (limited by utilization), and our staked balance
        return
            vault.convertToAssets(
                Math.min(vault.maxRedeem(gauge), balanceOfStake())
            );
    }

    // NOTE: only include this if we want to claim CRV on every report()
    //function _claimAndSellRewards() internal override {
    //    _claimRewards();
    //}

    /* ========== TRADE FACTORY FUNCTIONS ========== */

    function claimRewards() external override onlyManagement {
        _claimRewards();
    }

    function _claimRewards() internal override {
        // ***** IF WE WANTED TO DO NON-CRV CLAIMS, PROBABLY PUT THIS BEHIND FLAG
        proxy.harvest(gauge);

        // claim any extra rewards we may have beyond CRV
        if (rewardTokens().length > 1) {
            // technically we shouldn't pass CRV here, but since we know llama lend uses
            //  newer gauges, this won't be an issue in practice
            proxy.claimManyRewards(gauge, rewardTokens());
        }
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

    /* ========== PERMISSIONED FUNCTIONS ========== */

    /**
     * @notice Use this to set or update our strategy proxy.
     * @dev Only governance can set this.
     * @param _strategyProxy Address of our curve strategy proxy.
     */
    function setProxy(address _strategyProxy) external {
        require(msg.sender == GOV, "!gov");
        proxy = ICurveStrategyProxy(_strategyProxy);
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {IConvexBooster, IConvexRewards} from "./interfaces/ICrvusdInterfaces.sol";

contract StrategyLlamaLendConvex is Base4626Compounder, TradeFactorySwapper {
    using SafeERC20 for ERC20;

    /// @notice This is the deposit contract that all Convex pools use, aka booster.
    IConvexBooster public immutable booster;

    /// @notice This is unique to each pool and holds the rewards.
    IConvexRewards public immutable rewardsContract;

    /// @notice This is a unique numerical identifier for each Convex pool.
    uint256 public immutable pid;

    /// @notice Curve gauge address corresponding to our Curve Lend LP
    address public immutable gauge;

    /**
     * @param _asset Underlying asset to use for this strategy.
     * @param _name Name to use for this strategy. Ideally something human readable for a UI to use.
     * @param _vault ERC4626 vault token to use. In Curve Lend, these are the base LP tokens.
     * @param _pid PID for our Convex pool.
     * @param _booster Address for Convex's booster.
     */
    constructor(
        address _asset,
        string memory _name,
        address _vault,
        uint256 _pid,
        address _booster
    ) Base4626Compounder(_asset, _name, _vault) {
        // ideally this booster value is pre-filled using a factory (specific to each chain)
        booster = IConvexBooster(_booster);

        // pid is specific to each pool
        pid = _pid;

        // use our pid to pull the corresponding rewards contract and LP token
        (
            address lptoken,
            ,
            address _gauge,
            address _rewardsContract,
            ,

        ) = booster.poolInfo(_pid);
        rewardsContract = IConvexRewards(_rewardsContract);
        gauge = _gauge;

        // make sure we used the correct pid for our llama lend vault
        require(_vault == lptoken, "wrong pid");

        // approve LP deposits on the booster
        ERC20(_vault).forceApprove(_booster, type(uint256).max);
    }

    /* ========== BASE4626 FUNCTIONS ========== */

    /**
     * @notice Balance of 4626 vault tokens held in our strategy proxy
     */
    function balanceOfStake() public view override returns (uint256 stake) {
        stake = rewardsContract.balanceOf(address(this));
    }

    function _stake() internal override {
        // send any loose 4626 vault tokens to convex
        booster.deposit(pid, balanceOfVault(), true);
    }

    function _unStake(uint256 _amount) internal override {
        // _amount is already in 4626 vault shares, no need to convert from asset
        rewardsContract.withdrawAndUnwrap(_amount, false);
    }

    function vaultsMaxWithdraw() public view override returns (uint256) {
        // we use the gauge address here since that's where our strategy proxy deposits the LP
        // should be the minimum of what the gauge can redeem (limited by utilization), and our staked balance + loose vault tokens
        return
            vault.convertToAssets(
                Math.min(
                    vault.maxRedeem(gauge),
                    balanceOfStake() + balanceOfVault()
                )
            );
    }

    /* ========== TRADE FACTORY FUNCTIONS ========== */

    function claimRewards() external override onlyManagement {
        _claimRewards();
    }

    function _claimRewards() internal override {
        rewardsContract.getReward(address(this), true);
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

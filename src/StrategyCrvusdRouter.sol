// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {IYearnV2, ISharePriceHelper, IGauge} from "./interfaces/ICrvusdInterfaces.sol";

contract StrategyCrvusdRouter is Base4626Compounder {
    using SafeERC20 for ERC20;

    /// @notice Address of the Yearn Curve Lend factory vault.
    IYearnV2 public immutable yearnCurveLendVault;

    // helper contract to more accurately convert between assets and V2 vault shares
    ISharePriceHelper internal constant sharePriceHelper =
        ISharePriceHelper(0x444443bae5bB8640677A8cdF94CB8879Fec948Ec);

    // Curve gauge address corresponding to our Curve Lend LP
    address internal immutable gauge;

    /**
     * @param _asset Underlying asset to use for this strategy.
     * @param _name Name to use for this strategy. Ideally something human readable for a UI to use.
     * @param _vault ERC4626 vault token to use. In Curve Lend, these are the base LP tokens.
     * @param _gauge Gauge address for the Curve Lend LP.
     * @param _yearnCurveLendVault Address for the Curve Lend Yearn vault.
     */
    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _gauge,
        address _yearnCurveLendVault
    ) Base4626Compounder(_asset, _name, _vault) {
        yearnCurveLendVault = IYearnV2(_yearnCurveLendVault);
        require(_vault == yearnCurveLendVault.token(), "token mismatch");
        require(_vault == IGauge(_gauge).lp_token(), "gauge mismatch");
        gauge = _gauge;

        ERC20(_vault).forceApprove(_yearnCurveLendVault, type(uint256).max);
    }

    /* ========== BASE4626 FUNCTIONS ========== */

    /**
     * @notice Balance of 4626 vault tokens held in our yearn Curve Lend vault tokens
     * @dev Subtract 1 wei to account for rounding issues
     */
    function balanceOfStake() public view override returns (uint256 stake) {
        stake = sharePriceHelper.sharesToAmount(
            address(yearnCurveLendVault),
            yearnCurveLendVault.balanceOf(address(this))
        );
        if (stake > 0) {
            stake -= 1;
        }
    }

    function _stake() internal override {
        // deposit any loose 4626 vault tokens to the yearn curve lend vault
        uint256 toDeposit = balanceOfVault();

        // don't bother with dust to prevent issues with share conversion
        // curve lend vaults are 1:1000, so this is ~0.001 crvUSD
        if (toDeposit >= 1e18) {
            // pass the actual amount to avoid partial deposits
            yearnCurveLendVault.deposit(toDeposit);
        }
    }

    function _unStake(uint256 _amount) internal override {
        // _amount is already in 4626 vault shares, no need to convert from asset
        //  note that we do need to convert from 4626 vault shares to V2 vault shares
        // add 1 wei here to prevent loss from floor math
        uint256 sharesToWithdraw = sharePriceHelper.amountToShares(
            address(yearnCurveLendVault),
            _amount
        ) + 1;
        uint256 vaultTokenBalance = yearnCurveLendVault.balanceOf(
            address(this)
        );

        // can't withdraw more than we have
        if (sharesToWithdraw > vaultTokenBalance) {
            sharesToWithdraw = vaultTokenBalance;
        }

        // pass the actual amount
        yearnCurveLendVault.withdraw(sharesToWithdraw);
    }

    function vaultsMaxWithdraw() public view override returns (uint256) {
        // We need to use the staking contract address for maxRedeem
        // Convert the vault shares to `asset`.
        // we use the gauge address here since that's where our yearn curve lend vault sends the tokens
        // also include the vault itself since there may be loose funds waiting there
        return
            vault.convertToAssets(
                vault.maxRedeem(gauge) +
                    vault.maxRedeem(address(yearnCurveLendVault))
            );
    }

    function availableDepositLimit(
        address
    ) public view override returns (uint256) {
        uint256 limit = yearnCurveLendVault.depositLimit();
        uint256 assets = yearnCurveLendVault.totalAssets();

        uint256 underlyingLimit = vault.maxDeposit(address(this));
        uint256 yearnVaultLimit;

        if (limit > assets) {
            unchecked {
                yearnVaultLimit = vault.convertToAssets(limit - assets);
            }
        }

        return Math.min(underlyingLimit, yearnVaultLimit);
    }
}

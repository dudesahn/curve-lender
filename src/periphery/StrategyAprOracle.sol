// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

// example of FE APY calcs: https://github.com/Gearbox-protocol/sdk/blob/next/src/gearboxRewards/apy.ts
// https://github.com/Gearbox-protocol/defillama/blob/7127e015b2dc3f47043292e8801d01930560003c/src/yield-server/index.ts#L242

import {Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";

interface IStrategy {
    function vault() external view returns (address);

    function gauge() external view returns (address);
}

interface IVault {
    function pricePerShare() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function controller() external view returns (address);

    function amm() external view returns (address);
}

interface ICurvePeriphery {
    function total_debt() external view returns (uint256);

    function rate() external view returns (uint256);

    function gauge_relative_weight(address) external view returns (uint256);
}

interface IGauge {
    function inflation_rate() external view returns (uint256);

    function working_supply() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function working_balances(address) external view returns (uint256);

    function balanceOf(address) external view returns (uint256);
}

interface ICurvePool {
    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);
}

contract SimpleLlamaLendOracle {
    address internal constant TRI_CRV_USD_CURVE_POOL =
        0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;

    address internal constant GAUGE_CONTROLLER =
        0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB;

    address internal constant YEARN_VOTER =
        0xF147b8125d2ef93FB6965Db97D6746952a133934;

    address internal constant VE_CRV =
        0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;

    uint256 internal constant SECONDS_PER_YEAR = 31_556_952;

    /**
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view returns (uint256) {
        address vault = IStrategy(_strategy).vault();

        uint256 lend_apr = getLendingApr(vault, _delta);

        uint256 rewardYield;
        (, , rewardYield) = getCrvApr(_strategy, vault, _delta);

        // Return total APR (native yield + reward yield)
        return lend_apr + rewardYield;
    }

    function getLendingApr(
        address _vault,
        int256 _delta
    ) public view returns (uint256 lend_apr) {
        IVault vault = IVault(_vault);

        // Step 1: Calculate native yield
        uint256 assets = vault.totalAssets();
        if (_delta < 0) {
            assets = assets - uint256(-_delta);
        } else {
            assets = assets + uint256(_delta);
        }

        // code for lend_apr from curve vault
        // debt: uint256 = self.controller.total_debt()
        // self.amm.rate() * (365 * 86400) * debt / self._total_assets()

        lend_apr =
            (ICurvePeriphery(vault.amm()).rate() *
                (365 * 86400) *
                ICurvePeriphery(vault.controller()).total_debt()) /
            assets;
    }

    function getCrvApr(
        address _strategy,
        address _vault,
        int256 _delta
    ) public view returns (uint256 baseApr, uint256 boost, uint256 finalApr) {
        IStrategy strategy = IStrategy(_strategy);
        IGauge gauge = IGauge(strategy.gauge());
        IVault vault = IVault(_vault);

        // recreate CRV and Reward APR calculations from yDaemon/yExporter
        // tbh probbaly not worth doing the reward calculations yet since that will have to be custom per custom reward token

        uint256 gaugeWeight = ICurvePeriphery(GAUGE_CONTROLLER)
            .gauge_relative_weight(address(gauge));

        if (gaugeWeight == 0) {
            // no CRV emissions
            return (0, 1e18, 0);
        }

        // pull current values
        uint256 voterGaugeBalance = gauge.balanceOf(YEARN_VOTER);
        uint256 currentWorkingBalance = gauge.working_balances(YEARN_VOTER);
        uint256 totalSupply = gauge.totalSupply();
        uint256 currentWorkingSupply = gauge.working_supply();

        // adjust our voter gauge balance based on delta
        if (_delta < 0) {
            voterGaugeBalance = voterGaugeBalance - uint256(-_delta);
            totalSupply = totalSupply - uint256(-_delta);
        } else {
            voterGaugeBalance = voterGaugeBalance + uint256(_delta);
            totalSupply = totalSupply + uint256(_delta);
        }

        uint256 crvPrice = ICurvePool(TRI_CRV_USD_CURVE_POOL).get_dy(
            2,
            0,
            1e18
        );

        // we need to calculate working_balances from scratch to factor potential changes
        uint256 futureWorkingBalance = (voterGaugeBalance * 40) /
            100 +
            (totalSupply * IGauge(VE_CRV).balanceOf(YEARN_VOTER) * 60) /
            (IGauge(VE_CRV).totalSupply() * 100);
        futureWorkingBalance = Math.min(
            futureWorkingBalance,
            voterGaugeBalance
        );
        uint256 futureWorkingSupply = currentWorkingSupply +
            futureWorkingBalance -
            currentWorkingBalance;

        baseApr =
            (((10 * crvPrice * SECONDS_PER_YEAR * gauge.inflation_rate()) /
                futureWorkingSupply) * gaugeWeight) /
            (vault.pricePerShare() * 25);

        if (voterGaugeBalance == 0) {
            boost = 2.5e18;
        } else {
            boost =
                (futureWorkingBalance * 25 * 1e18) /
                (10 * voterGaugeBalance);
        }

        finalApr = (baseApr * boost) / 1e18;
    }
}

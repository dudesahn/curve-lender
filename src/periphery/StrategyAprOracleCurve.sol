// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "src/interfaces/IStrategyInterface.sol";
import {IVault, IController, IPeriphery, IGauge, IPool} from "src/interfaces/ICurveInterfaces.sol";

contract LlamaLendCurveOracle {
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
        address vault = IStrategyInterface(_strategy).vault();

        uint256 lend_apr = getLendingApr(vault, _delta);

        (, , uint256 rewardYield) = getCrvApr(_strategy, vault, _delta);

        // Return total APR (native yield + reward yield)
        return lend_apr + rewardYield;
    }

    function getLendingApr(
        address _vault,
        int256 _delta
    ) public view returns (uint256 lend_apr) {
        IVault vault = IVault(_vault);
        IController controller = IController(vault.controller());

        // Step 1: Calculate native yield
        uint256 assets = vault.totalAssets();
        if (_delta < 0) {
            // check how much free liquidity is in the AMM Controller. make sure we're not withdrawing more than that.
            uint256 freeLiquidity = IPeriphery(controller.borrowed_token())
                .balanceOf(address(controller));
            if (uint256(-_delta) > freeLiquidity) {
                return 0;
            }
            assets = assets - uint256(-_delta);
        } else {
            assets = assets + uint256(_delta);
        }

        if (assets == 0) {
            return 0;
        }

        // code for lend_apr from curve vault
        // debt: uint256 = self.controller.total_debt()
        // apr = self.amm.rate() * (365 * 86400) * debt / self._total_assets()

        // calculate the future rate from our deposit/withdrawal
        uint256 rate = IPeriphery(controller.monetary_policy()).future_rate(
            address(controller),
            _delta,
            0
        );
        rate = Math.min(43959106799, rate); // max of 300% APY hardcoded in controller

        lend_apr = (rate * (365 * 86400) * controller.total_debt()) / assets;
    }

    function getCrvApr(
        address _strategy,
        address _vault,
        int256 _delta
    ) public view returns (uint256 baseApr, uint256 boost, uint256 finalApr) {
        IStrategyInterface strategy = IStrategyInterface(_strategy);
        IGauge gauge = IGauge(strategy.gauge());
        IVault vault = IVault(_vault);

        uint256 gaugeWeight = IPeriphery(GAUGE_CONTROLLER)
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

        uint256 crvPrice = IPool(TRI_CRV_USD_CURVE_POOL).get_dy(2, 0, 1e18);

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

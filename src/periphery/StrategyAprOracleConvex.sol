// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "src/interfaces/IStrategyInterface.sol";
import {IVault, IPeriphery, IGauge, IPool} from "src/interfaces/ICurveInterfaces.sol";
import {IConvexRewards} from "src/interfaces/IConvexInterfaces.sol";
import {IOracle} from "src/interfaces/IChainlinkOracle.sol";

contract LlamaLendConvexOracle {
    address internal constant TRI_CRV_USD_CURVE_POOL =
        0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;

    address internal constant CVX_TOKEN =
        0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    address internal constant VE_CRV =
        0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;

    address internal constant GAUGE_CONTROLLER =
        0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB;

    address internal constant CONVEX_VOTER =
        0x989AEb4d175e16225E39E87d0D97A3360524AD80;

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

        (, , uint256 rewardYield) = getConvexApr(_strategy, vault, _delta);

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

        if (assets == 0) {
            return 0;
        }

        // code for lend_apr from curve vault
        // debt: uint256 = self.controller.total_debt()
        // self.amm.rate() * (365 * 86400) * debt / self._total_assets()

        lend_apr =
            (IPeriphery(vault.amm()).rate() *
                (365 * 86400) *
                IPeriphery(vault.controller()).total_debt()) /
            assets;
    }

    function getConvexApr(
        address _strategy,
        address _vault,
        int256 _delta
    ) public view returns (uint256 crvApr, uint256 cvxApr, uint256 finalApr) {
        IStrategyInterface strategy = IStrategyInterface(_strategy);
        IConvexRewards rewards = IConvexRewards(strategy.rewardsContract());
        IVault vault = IVault(_vault);
        uint256 totalSupply = rewards.totalSupply();

        // adjust our voter gauge balance based on delta
        if (_delta < 0) {
            totalSupply = totalSupply - uint256(-_delta);
        } else {
            totalSupply = totalSupply + uint256(_delta);
        }

        // pull CRV price from TriCRV pool
        uint256 crvPrice = IPool(TRI_CRV_USD_CURVE_POOL).get_dy(2, 0, 1e18);

        // pull CVX price from chainlink
        (, uint256 cvxPrice, , , ) = IOracle(
            0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf
        ).latestRoundData(
                CVX_TOKEN,
                0x0000000000000000000000000000000000000348 // USD, returns 1e8
            );

        // CRV per second on convex rewards pool
        uint256 rewardRate = rewards.rewardRate();
        uint256 denominator = totalSupply * vault.pricePerShare();

        // calculate APRs for each of the two tokens and then combine them
        if (denominator > 0 && rewards.periodFinish() > block.timestamp) {
            crvApr =
                (crvPrice * SECONDS_PER_YEAR * rewardRate * 1e18) /
                denominator;
            cvxApr =
                (cvxPrice * SECONDS_PER_YEAR * getCvxRate(rewardRate) * 1e28) /
                denominator;
        } else {
            // in case there's a pool whose rewards have lapsed or convex has no TVL, use projected CRV rewards only
            // assuming there are actual CRV rewards, CVX rewards will be factored in again once they are flowing
            (, , crvApr) = getCrvApr(_strategy, _vault, _delta);
        }
        finalApr = crvApr + cvxApr;
    }

    function getCvxRate(
        uint256 _crvPerSecond
    ) public view returns (uint256 cvxRate) {
        // calculations pulled directly from CVXs contract for minting CVX per CRV claimed
        uint256 totalCliffs = 1_000;
        uint256 maxSupply; // 100mil
        unchecked {
            maxSupply = 100 * 1_000_000 * 1e18;
        }
        uint256 reductionPerCliff; // 100,000
        unchecked {
            reductionPerCliff = 100_000 * 1e18;
        }
        uint256 supply = IConvexRewards(CVX_TOKEN).totalSupply(); // CVX total supply
        uint256 mintableCvx;

        uint256 cliff;
        unchecked {
            cliff = supply / reductionPerCliff;
        }

        // mint if below total cliffs
        if (cliff < totalCliffs) {
            uint256 reduction; // for reduction% take inverse of current cliff
            unchecked {
                reduction = totalCliffs - cliff;
            }
            // reduce
            unchecked {
                mintableCvx = (_crvPerSecond * reduction) / totalCliffs;
            }

            uint256 amtTillMax; // supply cap check
            unchecked {
                amtTillMax = maxSupply - supply;
            }
            if (mintableCvx > amtTillMax) {
                mintableCvx = amtTillMax;
            }
        }

        cvxRate = mintableCvx;
    }

    // use this only in the edge case convex has no deposits
    function getCrvApr(
        address _strategy,
        address _vault,
        int256 _delta
    ) public view returns (uint256 baseApr, uint256 boost, uint256 finalApr) {
        IStrategyInterface strategy = IStrategyInterface(_strategy);
        IGauge gauge = IGauge(strategy.gauge());
        IVault vault = IVault(_vault);

        // recreate CRV and Reward APR calculations from yDaemon/yExporter
        // tbh probbaly not worth doing the reward calculations yet since that will have to be custom per custom reward token

        uint256 gaugeWeight = IPeriphery(GAUGE_CONTROLLER)
            .gauge_relative_weight(address(gauge));

        if (gaugeWeight == 0) {
            // no CRV emissions
            return (0, 1e18, 0);
        }

        // pull current values. in this scenario, we assume convex has no gauge deposits
        uint256 voterGaugeBalance = gauge.balanceOf(CONVEX_VOTER);
        uint256 currentWorkingBalance = gauge.working_balances(CONVEX_VOTER);
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
            (totalSupply * IGauge(VE_CRV).balanceOf(CONVEX_VOTER) * 60) /
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

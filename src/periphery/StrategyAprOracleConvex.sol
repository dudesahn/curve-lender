// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

// example of FE APY calcs: https://github.com/Gearbox-protocol/sdk/blob/next/src/gearboxRewards/apy.ts
// https://github.com/Gearbox-protocol/defillama/blob/7127e015b2dc3f47043292e8801d01930560003c/src/yield-server/index.ts#L242

import {Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";

interface IStrategy {
    function vault() external view returns (address);

    function rewardsContract() external view returns (address);
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
}

interface IRewards {
    function totalSupply() external view returns (uint256);

    function rewardRate() external view returns (uint256);
}

interface ICurvePool {
    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);
}

interface IOracle {
    function latestRoundData(
        address,
        address
    )
        external
        view
        returns (
            uint80 roundId,
            uint256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract SimpleLlamaLendOracle {
    address internal constant TRI_CRV_USD_CURVE_POOL =
        0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;

    address internal constant CVX_TOKEN =
        0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

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

        // code for lend_apr from curve vault
        // debt: uint256 = self.controller.total_debt()
        // self.amm.rate() * (365 * 86400) * debt / self._total_assets()

        lend_apr =
            (ICurvePeriphery(vault.amm()).rate() *
                (365 * 86400) *
                ICurvePeriphery(vault.controller()).total_debt()) /
            assets;
    }

    function getConvexApr(
        address _strategy,
        address _vault,
        int256 _delta
    ) public view returns (uint256 crvApr, uint256 cvxApr, uint256 finalApr) {
        IStrategy strategy = IStrategy(_strategy);
        IRewards rewards = IRewards(strategy.rewardsContract());
        IVault vault = IVault(_vault);

        // recreate CRV and Reward APR calculations from yDaemon/yExporter
        // tbh probbaly not worth doing the reward calculations yet since that will have to be custom per custom reward token

        uint256 totalSupply = rewards.totalSupply();

        // adjust our voter gauge balance based on delta
        if (_delta < 0) {
            totalSupply = totalSupply - uint256(-_delta);
        } else {
            totalSupply = totalSupply + uint256(_delta);
        }

        // pull CRV price from TriCRV pool
        uint256 crvPrice = ICurvePool(TRI_CRV_USD_CURVE_POOL).get_dy(
            2,
            0,
            1e18
        );

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
        crvApr =
            (crvPrice * SECONDS_PER_YEAR * rewardRate * 1e18) /
            denominator;
        cvxApr =
            (cvxPrice * SECONDS_PER_YEAR * getCvxRate(rewardRate) * 1e28) /
            denominator;
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
        uint256 supply = IRewards(CVX_TOKEN).totalSupply(); // CVX total supply
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
}

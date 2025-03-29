pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ERC20, Setup} from "./utils/Setup.sol";
import {FraxLend4626Oracle} from "../periphery/FraxLend4626Oracle.sol";

interface ICurveVault {
    function collateral_token() external view returns (address);
}

contract OracleTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function checkOracle(
        address _strategy,
        uint256 _delta
    ) public returns (uint256 currentApr) {
        // don't bother testing our oracle if we don't have yield
        // NOTE: we don't currently consider extra token rewards. if needed, update oracle to add these in.
        if (noBaseYield && noCrvYield) {
            return 0;
        }

        if (useConvex) {
            // if a convex rewards contract has tiny supply, just return (added because uWu is empty w/ old rewards)
            if (
                ERC20(strategy.rewardsContract()).totalSupply() < 1_000_000e18
            ) {
                // note this is really just 1000 crvUSD, since deposits are diluted 1000:1
                return 0;
            }

            currentApr = convexOracle.aprAfterDebtChange(_strategy, 0);
            uint256 testLendingApr = convexOracle.getLendingApr(
                strategy.vault(),
                0
            );
            (
                uint256 testCrveApr,
                uint256 testConvexApr,
                uint256 testFinalApr
            ) = convexOracle.getConvexApr(
                    address(strategy),
                    strategy.vault(),
                    0
                );

            // Should be greater than 0 but likely less than 50%
            assertLt(testLendingApr, 5e17, "lending +50%");
            assertLt(testCrveApr, 5e17, "curve +50%");
            assertLt(testConvexApr, 5e17, "convex +50%");
            assertLt(testFinalApr, 5e17, "final +50%");
            assertGt(currentApr, 0, "ZERO");
            assertLt(currentApr, 5e17, "fart +50%");

            // no need to do anything else if we're not changing
            if (_delta != 0) {
                uint256 negativeDebtChangeApr = convexOracle.aprAfterDebtChange(
                    _strategy,
                    -int256(_delta)
                );

                // The apr should go up if deposits go down
                assertLt(currentApr, negativeDebtChangeApr, "negative change");

                uint256 positiveDebtChangeApr = convexOracle.aprAfterDebtChange(
                    _strategy,
                    int256(_delta)
                );

                // The apr should go down if deposits go up
                assertGt(currentApr, positiveDebtChangeApr, "positive change");
            }
        } else {
            currentApr = oracle.aprAfterDebtChange(_strategy, 0);

            // Should be greater than 0 but likely less than 100%
            assertGt(currentApr, 0, "ZERO");
            assertLt(currentApr, 1e18, "+100%");

            // no need to do anything else if we're not changing
            if (_delta != 0) {
                uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(
                    _strategy,
                    -int256(_delta)
                );

                // The apr should go up if deposits go down
                assertLt(currentApr, negativeDebtChangeApr, "negative change");

                uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(
                    _strategy,
                    int256(_delta)
                );

                // The apr should go down if deposits go up
                assertGt(currentApr, positiveDebtChangeApr, "positive change");
            }
        }
    }

    function test_oracle_fuzzy(uint256 _amount, uint16 _percentChange) public {
        // go a bit higher with min amount, otherwise APRs might stay the same at very low deposits
        vm.assume(_amount > minAprOracleFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 _delta = (_amount * _percentChange) / MAX_BPS;

        checkOracle(address(strategy), _delta);
    }

    function test_oracle_constant() public {
        console2.log(
            "Collateral asset",
            ERC20(ICurveVault(strategy.vault()).collateral_token()).name()
        );

        // we can pull APR without TVL
        uint256 strategyApr = checkOracle(address(strategy), 0);
        uint256 lendingApr;

        if (useConvex) {
            (uint256 crvApr, uint256 cvxApr, uint256 finalApr) = convexOracle
                .getConvexApr(address(strategy), strategy.vault(), 0);
            lendingApr = convexOracle.getLendingApr(strategy.vault(), 0);
            console2.log("total lending + crv APR: %e", strategyApr);
            console2.log("lending APR: %e", lendingApr);
            console2.log("crvApr: %e", crvApr);
            console2.log("cvxApr: %e", cvxApr);
            console2.log("finalApr: %e", finalApr);
        } else {
            (uint256 baseCrvApr, uint256 boost, uint256 boostedCrvApr) = oracle
                .getCrvApr(address(strategy), strategy.vault(), 0);
            lendingApr = oracle.getLendingApr(strategy.vault(), 0);
            console2.log("total lending + crv APR: %e", strategyApr);
            console2.log("lending APR: %e", lendingApr);
            console2.log("baseCrvApr: %e", baseCrvApr);
            console2.log("boost: %e", boost);
            console2.log("boostedCrvApr: %e", boostedCrvApr);
        }

        // whale causes max util, so our interest should PAMP
        bool isMaxUtil = causeMaxUtil();
        if (!isMaxUtil) {
            console2.log("Skip test, not max util for this market");
            return;
        } else {
            console2.log("Max util to pump interest rate");
            uint256 newLendingApr;
            if (useConvex) {
                newLendingApr = convexOracle.getLendingApr(strategy.vault(), 0);
            } else {
                newLendingApr = oracle.getLendingApr(strategy.vault(), 0);
            }
            console2.log("max lending APR: %e", newLendingApr);
            assertGt(newLendingApr, lendingApr, "!maxutil");
        }
    }

    function test_oracle_decrease_debt() public {
        // don't bother testing our oracle if we don't have yield
        if (noBaseYield && noCrvYield) {
            return;
        }
        console2.log(
            "Collateral asset",
            ERC20(ICurveVault(strategy.vault()).collateral_token()).name()
        );
        mintAndDepositIntoStrategy(strategy, user, 100_000e18);

        uint256 strategyApr = checkOracle(address(strategy), 0);

        if (useConvex) {
            (uint256 crvApr, uint256 cvxApr, uint256 finalApr) = convexOracle
                .getConvexApr(address(strategy), strategy.vault(), 0);
            uint256 lendingApr = convexOracle.getLendingApr(
                strategy.vault(),
                0
            );
            console2.log("total lending + crv APR: %e", strategyApr);
            console2.log("lending APR: %e", lendingApr);
            console2.log("crvApr: %e", crvApr);
            console2.log("cvxApr: %e", cvxApr);
            console2.log("finalApr: %e", finalApr);

            // pull our overall and CRV-specific APRs
            uint256 negativeDebtChangeApr = convexOracle.aprAfterDebtChange(
                address(strategy),
                -int256(50_000e18)
            );
            (
                uint256 negativeCrvApr,
                uint256 negativeCvxApr,
                uint256 negativeFinalApr
            ) = convexOracle.getConvexApr(
                    address(strategy),
                    strategy.vault(),
                    -int256(50_000e18)
                );
            uint256 negativeLendingApr = convexOracle.getLendingApr(
                strategy.vault(),
                -int256(50_000e18)
            );

            // print
            console2.log(
                "Halve debt, total lending + crv APR: %e",
                negativeDebtChangeApr
            );
            console2.log("Halve debt, lending APR: %e", negativeLendingApr);
            console2.log("Halve debt, crvApr: %e", negativeCrvApr);
            console2.log("Halve debt, cvxApr: %e", negativeCvxApr);
            console2.log("Halve debt, finalApr: %e", negativeFinalApr);

            // The apr should go up if deposits go down
            assertLt(strategyApr, negativeDebtChangeApr, "negative change");
            assertLt(lendingApr, negativeLendingApr, "negative change");
            if (crvApr > 0) {
                // don't check these if no CRV emissions
                assertLt(crvApr, negativeCrvApr, "negative change");
                assertLe(cvxApr, negativeCvxApr, "negative change"); // CVX can be the same if we need to notify
                assertLt(finalApr, negativeFinalApr, "negative change");
            }
        } else {
            (uint256 baseCrvApr, uint256 boost, uint256 boostedCrvApr) = oracle
                .getCrvApr(address(strategy), strategy.vault(), 0);
            uint256 lendingApr = oracle.getLendingApr(strategy.vault(), 0);

            // print
            console2.log("total lending + crv APR: %e", strategyApr);
            console2.log("lending APR: %e", lendingApr);
            console2.log("baseCrvApr: %e", baseCrvApr);
            console2.log("boost: %e", boost);
            console2.log("boostedCrvApr: %e", boostedCrvApr);

            // pull our overall and CRV-specific APRs
            uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(
                address(strategy),
                -int256(50_000e18)
            );
            (
                uint256 negativebaseCrvApr,
                uint256 negativeBoost,
                uint256 negativeboostedCrvApr
            ) = oracle.getCrvApr(
                    address(strategy),
                    strategy.vault(),
                    -int256(50_000e18)
                );
            uint256 negativeLendingApr = oracle.getLendingApr(
                strategy.vault(),
                -int256(50_000e18)
            );

            // print
            console2.log(
                "Halve debt, total lending + crv APR: %e",
                negativeDebtChangeApr
            );
            console2.log("Halve debt, lending APR: %e", negativeLendingApr);
            console2.log("Halve debt, baseCrvApr: %e", negativebaseCrvApr);
            console2.log("Halve debt, boost: %e", negativeBoost);
            console2.log(
                "Halve debt, boostedCrvApr: %e",
                negativeboostedCrvApr
            );

            // The apr should go up if deposits go down
            assertLt(strategyApr, negativeDebtChangeApr, "negative change");
            assertLt(lendingApr, negativeLendingApr, "negative change");
            if (baseCrvApr > 0) {
                // don't check these if no CRV emissions
                assertLt(baseCrvApr, negativebaseCrvApr, "negative change");
                assertLe(boost, negativeBoost, "negative change"); // boost could stay fully boosted
                assertLt(
                    boostedCrvApr,
                    negativeboostedCrvApr,
                    "negative change"
                );
            }
        }
    }

    function test_oracle_increase_debt() public {
        // don't bother testing our oracle if we don't have yield
        if (noBaseYield && noCrvYield) {
            return;
        }
        console2.log(
            "Collateral asset",
            ERC20(ICurveVault(strategy.vault()).collateral_token()).name()
        );
        mintAndDepositIntoStrategy(strategy, user, 100_000e18);

        uint256 strategyApr = checkOracle(address(strategy), 0);

        if (useConvex) {
            (uint256 crvApr, uint256 cvxApr, uint256 finalApr) = convexOracle
                .getConvexApr(address(strategy), strategy.vault(), 0);
            uint256 lendingApr = convexOracle.getLendingApr(
                strategy.vault(),
                0
            );
            console2.log("total lending + crv APR: %e", strategyApr);
            console2.log("lending APR: %e", lendingApr);
            console2.log("crvApr: %e", crvApr);
            console2.log("cvxApr: %e", cvxApr);
            console2.log("finalApr: %e", finalApr);

            // pull our overall and CRV-specific APRs
            uint256 positiveDebtChangeApr = convexOracle.aprAfterDebtChange(
                address(strategy),
                int256(100_000e18)
            );
            (
                uint256 positiveCrvApr,
                uint256 positiveCvxApr,
                uint256 positiveFinalApr
            ) = convexOracle.getConvexApr(
                    address(strategy),
                    strategy.vault(),
                    int256(100_000e18)
                );
            uint256 positiveLendingApr = convexOracle.getLendingApr(
                strategy.vault(),
                int256(100_000e18)
            );
            console2.log(
                "Double debt, total lending + crv APR: %e",
                positiveDebtChangeApr
            );
            console2.log("Double debt, lending APR: %e", positiveLendingApr);
            console2.log("Double debt, crvApr: %e", positiveCrvApr);
            console2.log("Double debt, cvxApr: %e", positiveCvxApr);
            console2.log("Double debt, finalApr: %e", positiveFinalApr);

            // The apr should go down if deposits go up
            assertGt(strategyApr, positiveDebtChangeApr, "positive change");
            assertGt(lendingApr, positiveLendingApr, "positive change");
            if (crvApr > 0) {
                // don't check these if no CRV emissions
                assertGt(crvApr, positiveCrvApr, "positive change");
                assertGe(cvxApr, positiveCvxApr, "positive change"); // CVX can be the same if we need to notify
                assertGt(finalApr, positiveFinalApr, "positive change");
            }
        } else {
            (uint256 baseCrvApr, uint256 boost, uint256 boostedCrvApr) = oracle
                .getCrvApr(address(strategy), strategy.vault(), 0);
            uint256 lendingApr = oracle.getLendingApr(strategy.vault(), 0);
            console2.log("total lending + crv APR: %e", strategyApr);
            console2.log("lending APR: %e", lendingApr);
            console2.log("baseCrvApr: %e", baseCrvApr);
            console2.log("boost: %e", boost);
            console2.log("boostedCrvApr: %e", boostedCrvApr);

            // pull our overall and CRV-specific APRs
            uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(
                address(strategy),
                int256(100_000e18)
            );
            (
                uint256 positivebaseCrvApr,
                uint256 positiveBoost,
                uint256 positiveboostedCrvApr
            ) = oracle.getCrvApr(
                    address(strategy),
                    strategy.vault(),
                    int256(100_000e18)
                );
            uint256 positiveLendingApr = oracle.getLendingApr(
                strategy.vault(),
                int256(100_000e18)
            );
            console2.log(
                "Double debt, total lending + crv APR: %e",
                positiveDebtChangeApr
            );
            console2.log("Double debt, lending APR: %e", positiveLendingApr);
            console2.log("Double debt, baseCrvApr: %e", positivebaseCrvApr);
            console2.log("Double debt, boost: %e", positiveBoost);
            console2.log(
                "Double debt, boostedCrvApr: %e",
                positiveboostedCrvApr
            );

            // The apr should go down if deposits go up
            assertGt(strategyApr, positiveDebtChangeApr, "positive change");
            assertGt(lendingApr, positiveLendingApr, "positive change");
            if (baseCrvApr > 0) {
                // don't check these if no CRV emissions
                assertGt(baseCrvApr, positivebaseCrvApr, "positive change");
                assertGe(boost, positiveBoost, "positive change"); // boost could stay fully boosted
                assertGt(
                    boostedCrvApr,
                    positiveboostedCrvApr,
                    "positive change"
                );
            }
        }
    }

    function test_frax_oracle() public {
        // don't bother testing our oracle if we don't have yield
        address _strategy = 0x8E5f09de0cD7841239410F929A905E214443d9E0;
        FraxLend4626Oracle fraxOracle = new FraxLend4626Oracle();
        uint256 currentApr = fraxOracle.aprAfterDebtChange(_strategy, 0);

        // Should be greater than 0 but likely less than 100%
        assertGt(currentApr, 0, "ZERO");
        assertLt(currentApr, 1e18, "+100%");
        console2.log("Current Frax APR:", currentApr);
        
        // set our delta
        uint256 _delta = 1_000e18;

        uint256 negativeDebtChangeApr = fraxOracle.aprAfterDebtChange(
            _strategy,
            -int256(_delta)
        );

        // The apr should go up if deposits go down
        assertLt(currentApr, negativeDebtChangeApr, "negative change");

        uint256 positiveDebtChangeApr = fraxOracle.aprAfterDebtChange(
            _strategy,
            int256(_delta)
        );

        // The apr should go down if deposits go up
        assertGt(currentApr, positiveDebtChangeApr, "positive change");
    }
}

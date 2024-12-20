pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ERC20, Setup} from "./utils/Setup.sol";

import {SimpleLlamaLendOracle} from "../periphery/StrategyAprOracle.sol";

interface ICurveVault {
    function collateral_token() external view returns (address);
}

contract OracleTest is Setup {
    SimpleLlamaLendOracle public oracle;

    function setUp() public override {
        super.setUp();
        oracle = new SimpleLlamaLendOracle();
    }

    function checkOracle(
        address _strategy,
        uint256 _delta
    ) public returns (uint256 currentApr) {
        // Check set up
        // TODO: Add checks for the setup

        currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        // Should be greater than 0 but likely less than 100%
        assertGt(currentApr, 0, "ZERO");
        assertLt(currentApr, 1e18, "+100%");

        // no need to do anything else if we're not changing
        if (_delta != 0) {
            // TODO: Uncomment to test the apr goes up and down based on debt changes
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

            assertGt(currentApr, positiveDebtChangeApr, "positive change");
        }

        // TODO: Uncomment if there are setter functions to test.
        /**
        vm.expectRevert("!governance");
        vm.prank(user);
        oracle.setterFunction(setterVariable);

        vm.prank(management);
        oracle.setterFunction(setterVariable);

        assertEq(oracle.setterVariable(), setterVariable);
        */
    }

    function test_oracle(uint256 _amount, uint16 _percentChange) public {
        // go a bit higher with min amount, otherwise APRs might stay the same at very low deposits
        vm.assume(_amount > 1e18 && _amount < maxFuzzAmount);
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
        (uint256 baseCrvApr, uint256 boost, uint256 boostedCrvApr) = oracle
            .getCrvApr(address(strategy), strategy.vault(), 0);
        uint256 lendingApr = oracle.getLendingApr(strategy.vault(), 0);
        console2.log("total lending + crv APR: %e", strategyApr);
        console2.log("lending APR: %e", lendingApr);
        console2.log("baseCrvApr: %e", baseCrvApr);
        console2.log("boost: %e", boost);
        console2.log("boostedCrvApr: %e", boostedCrvApr);
    }

    function test_oracle_constant_decrease_debt() public {
        console2.log(
            "Collateral asset",
            ERC20(ICurveVault(strategy.vault()).collateral_token()).name()
        );
        mintAndDepositIntoStrategy(strategy, user, 100_000e18);

        uint256 strategyApr = checkOracle(address(strategy), 0);
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
        console2.log("Halve debt, boostedCrvApr: %e", negativeboostedCrvApr);

        // The apr should go up if deposits go down
        assertLt(strategyApr, negativeDebtChangeApr, "negative change");
        assertLt(lendingApr, negativeLendingApr, "negative change");
        if (baseCrvApr > 0) {
            // don't check these if no CRV emissions
            assertLt(baseCrvApr, negativebaseCrvApr, "negative change");
            assertLe(boost, negativeBoost, "negative change"); // boost could stay fully boosted
            assertLt(boostedCrvApr, negativeboostedCrvApr, "negative change");
        }
    }

    function test_oracle_constant_increase_debt() public {
        console2.log(
            "Collateral asset",
            ERC20(ICurveVault(strategy.vault()).collateral_token()).name()
        );
        mintAndDepositIntoStrategy(strategy, user, 100_000e18);

        uint256 strategyApr = checkOracle(address(strategy), 0);
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
        console2.log("Double debt, boostedCrvApr: %e", positiveboostedCrvApr);

        // The apr should go down if deposits go up
        assertGt(strategyApr, positiveDebtChangeApr, "positive change");
        assertGt(lendingApr, positiveLendingApr, "positive change");
        if (baseCrvApr > 0) {
            // don't check these if no CRV emissions
            assertGt(baseCrvApr, positivebaseCrvApr, "positive change");
            assertGe(boost, positiveBoost, "positive change"); // boost could stay fully boosted
            assertGt(boostedCrvApr, positiveboostedCrvApr, "positive change");
        }
    }

    // TODO: Deploy multiple strategies with different tokens as `asset` to test against the oracle.
}

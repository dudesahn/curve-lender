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

        currentApr = oracle.aprAfterDebtChange(_strategy, int256(_delta));

        // Should be greater than 0 but likely less than 100%
        assertGt(currentApr, 0, "ZERO");
        assertLt(currentApr, 1e18, "+100%");

        // TODO: Uncomment to test the apr goes up and down based on debt changes
        /**
        uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(_strategy, -int256(_delta));

        // The apr should go up if deposits go down
        assertLt(currentApr, negativeDebtChangeApr, "negative change");

        uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(_strategy, int256(_delta));

        assertGt(currentApr, positiveDebtChangeApr, "positive change");
        */

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
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
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
        mintAndDepositIntoStrategy(strategy, user, 1e18);

        uint256 strategyApr = checkOracle(address(strategy), 0);
        console2.log("APR from oracle: %e", strategyApr);
        (uint256 baseApr, uint256 boost, uint256 finalApr) = oracle.getCrvApr(
            address(strategy),
            strategy.vault(),
            0
        );
        console2.log("baseApr: %e", baseApr);
        console2.log("boost: %e", boost);
        console2.log("finalApr: %e", finalApr);
    }

    // TODO: Deploy multiple strategies with different tokens as `asset` to test against the oracle.
}

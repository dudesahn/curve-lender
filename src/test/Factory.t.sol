// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {LlamaLendCurveFactory} from "../LlamaLendCurveFactory.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract FactoryTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    // no need for explicit factory testing since we use the factory to deploy strategies in Setup.sol
    function test_factory_status() public {
        // confirm our mapping works
        if (useConvex) {
            assertEq(
                convexFactory.deployments(strategy.vault()),
                address(strategy)
            );
            assertEq(true, convexFactory.isDeployedStrategy(address(strategy)));
            assertEq(false, convexFactory.isDeployedStrategy(user));
        } else {
            assertEq(
                curveFactory.deployments(strategy.vault()),
                address(strategy)
            );
            assertEq(true, curveFactory.isDeployedStrategy(address(strategy)));
            assertEq(false, convexFactory.isDeployedStrategy(user));

            // shouldn't be able to deploy another strategy for the same gauge for curve factory
            vm.expectRevert("strategy exists");
            vm.prank(management);
            curveFactory.newCurveLender(
                "Curve Boosted crvUSD-sDOLA Lender",
                curveLendVault,
                curveLendGauge
            );
        }

        assertEq(strategy.management(), management);
        assertEq(strategy.pendingManagement(), address(0));
        assertEq(strategy.performanceFee(), 1000);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.profitMaxUnlockTime(), profitMaxUnlockTime);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/console2.sol";
import {LlamaLendCurveFactory} from "src/LlamaLendCurveFactory.sol";
import {Setup, ERC20, IStrategyInterface} from "src/test/utils/Setup.sol";

contract FactoryTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    // no need for explicit factory testing since we use the factory to deploy strategies in Setup.sol
    function test_factory_status() public {
        // use this to check that our operator can deploy (need a different market)
        address otherCurveLendVault;
        address otherCurveLendGauge;
        uint256 otherPid;
        if (useMarket == 0) {
            otherCurveLendVault = 0x14361C243174794E2207296a6AD59bb0Dec1d388;
            otherCurveLendGauge = 0x30e06CADFbC54d61B7821dC1e58026bf3435d2Fe;
            otherPid = 384;
        } else {
            otherCurveLendVault = 0x21CF1c5Dc48C603b89907FE6a7AE83EA5e3709aF;
            otherCurveLendGauge = 0x0621982CdA4fD4041964e91AF4080583C5F099e1;
            otherPid = 364;

            // we have to clear this out before we set associate our new strategy with the gauge
            // don't worry about clearing out TVL like in setup.sol, we're just testing deployment here
            vm.prank(chad);
            // remove the strategy-gauge linkage on the strategy proxy
            strategyProxy.revokeStrategy(otherCurveLendGauge);
        }

        // set our operator to SMS
        address operator = emergencyAdmin;

        if (useConvex) {
            // confirm our mapping works
            assertEq(
                convexFactory.deployments(strategy.vault()),
                address(strategy)
            );
            assertEq(true, convexFactory.isDeployedStrategy(address(strategy)));
            assertEq(false, convexFactory.isDeployedStrategy(user));

            // shouldn't be able to deploy another strategy for the same vault
            vm.expectRevert("strategy exists");
            vm.prank(management);
            convexFactory.newConvexLender(
                "Convex crvUSD-sDOLA Lender",
                curveLendVault,
                pid
            );

            // but we can deploy for another vault
            // make sure operator can't deploy yet
            vm.expectRevert("!authorized");
            vm.prank(operator);
            convexFactory.newConvexLender(
                "Convex crvUSD-sDOLA Lender",
                otherCurveLendVault,
                otherPid
            );

            // now set operator address
            vm.prank(operator);
            vm.expectRevert("!management");
            curveFactory.setAddresses(
                management,
                performanceFeeRecipient,
                keeper,
                emergencyAdmin,
                operator
            );
            vm.startPrank(management);
            vm.expectRevert("ZERO_ADDRESS");
            convexFactory.setAddresses(
                address(0),
                performanceFeeRecipient,
                keeper,
                emergencyAdmin,
                operator
            );
            vm.expectRevert("ZERO_ADDRESS");
            convexFactory.setAddresses(
                management,
                address(0),
                keeper,
                emergencyAdmin,
                operator
            );
            vm.expectRevert("ZERO_ADDRESS");
            curveFactory.setAddresses(
                management,
                performanceFeeRecipient,
                keeper,
                address(0),
                operator
            );
            convexFactory.setAddresses(
                management,
                performanceFeeRecipient,
                keeper,
                emergencyAdmin,
                operator
            );
            vm.stopPrank();

            // don't deploy with the wrong pid
            vm.prank(operator);
            vm.expectRevert("wrong pid");
            convexFactory.newConvexLender(
                "Convex crvUSD-sDOLA Lender",
                otherCurveLendVault,
                pid
            );

            // now we should be able to deploy via operator
            vm.prank(operator);
            convexFactory.newConvexLender(
                "Convex crvUSD-sDOLA Lender",
                otherCurveLendVault,
                otherPid
            );
        } else {
            // confirm our mapping works
            assertEq(
                curveFactory.deployments(strategy.vault()),
                address(strategy)
            );
            assertEq(true, curveFactory.isDeployedStrategy(address(strategy)));
            assertEq(false, curveFactory.isDeployedStrategy(user));

            // shouldn't be able to deploy another strategy for the same gauge for curve factory
            vm.expectRevert("strategy exists");
            vm.prank(management);
            curveFactory.newCurveLender(
                "Curve Boosted crvUSD-sDOLA Lender",
                curveLendVault,
                curveLendGauge
            );

            // make sure operator can't deploy yet
            vm.expectRevert("!authorized");
            vm.prank(operator);
            curveFactory.newCurveLender(
                "Curve Boosted crvUSD-sDOLA Lender",
                otherCurveLendVault,
                otherCurveLendGauge
            );

            // now set operator address
            vm.prank(operator);
            vm.expectRevert("!management");
            curveFactory.setAddresses(
                management,
                performanceFeeRecipient,
                keeper,
                emergencyAdmin,
                operator
            );
            vm.startPrank(management);
            vm.expectRevert("ZERO_ADDRESS");
            curveFactory.setAddresses(
                address(0),
                performanceFeeRecipient,
                keeper,
                emergencyAdmin,
                operator
            );
            vm.expectRevert("ZERO_ADDRESS");
            curveFactory.setAddresses(
                management,
                address(0),
                keeper,
                emergencyAdmin,
                operator
            );
            vm.expectRevert("ZERO_ADDRESS");
            curveFactory.setAddresses(
                management,
                performanceFeeRecipient,
                keeper,
                address(0),
                operator
            );
            curveFactory.setAddresses(
                management,
                performanceFeeRecipient,
                keeper,
                emergencyAdmin,
                operator
            );
            vm.stopPrank();

            // now we should be able to deploy via operator
            vm.prank(operator);
            curveFactory.newCurveLender(
                "Convex crvUSD-sDOLA Lender",
                otherCurveLendVault,
                otherCurveLendGauge
            );
        }

        assertEq(strategy.management(), management);
        assertEq(strategy.pendingManagement(), address(0));
        assertEq(strategy.performanceFee(), 1000);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.profitMaxUnlockTime(), profitMaxUnlockTime);
    }
}

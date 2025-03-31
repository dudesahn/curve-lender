// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, Auction, IStrategyInterface} from "src/test/utils/Setup.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    // note that this test only considers base yield (underlying lending APR)
    function test_operation_fuzzy(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // turn off health check if no yield since we may lose 1 wei from rounding
        if (noBaseYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        if (noBaseYield) {
            assertGe(profit, 0, "!profit");
            assertLe(loss, 1, "!loss");
        } else {
            assertGt(profit, 0, "!profit");
            assertEq(loss, 0, "!loss");
        }

        // skip time to unlock any profit we've earned
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");
            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            vm.prank(user);
            strategy.withdraw(userToWithdraw, user, user);

            // check and make sure that our user still holds some amount of strategy tokens
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / 1e36;
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                1e36;
            // these should be equal, but give 1e9 wei of wiggle room for rounding
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 1e9);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);

            if (noBaseYield && noCrvYield && !hasRewards) {
                assertGe(
                    asset.balanceOf(user) + 1, // 1 wei loss for 4626 rounding
                    balanceBefore + _amount,
                    "!final balance"
                );
            } else {
                assertGe(
                    asset.balanceOf(user),
                    balanceBefore + _amount,
                    "!final balance"
                );
            }
        }
    }

    // test a fixed deposit amount so we can see our logs, just base yield
    function test_operation_base() public {
        uint256 _amount = 10_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // make sure the gauge tokens are in the voter for curve strategy
        if (useConvex == false) {
            uint256 gaugeBalance = ERC20(strategy.gauge()).balanceOf(voter);
            assertGt(gaugeBalance, 0, "!gaugeVoter");
        }

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // turn off health check if no yield since we may lose 1 wei from rounding
        if (noBaseYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log(
            "Profit from basic report:",
            profit / 1e18,
            "* 1e18 crvUSD"
        );
        uint256 roughApr = (((profit * 365) /
            (strategy.profitMaxUnlockTime() / 86400)) * 10_000) / _amount;
        console2.log("Rough APR from basic report:", roughApr, "BPS");
        console2.log(
            "Days to unlock profit:",
            strategy.profitMaxUnlockTime() / 86400
        );

        // Check return Values
        if (noBaseYield) {
            assertGe(profit, 0, "!profit");
            assertLe(loss, 1, "!loss");
        } else {
            assertGt(profit, 0, "!profit");
            assertEq(loss, 0, "!loss");
        }

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");
            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            vm.prank(user);
            strategy.withdraw(userToWithdraw, user, user);

            // check and make sure that our user still holds some amount of strategy tokens
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / 1e36;
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                1e36;
            // these should be equal, but give 1e9 wei of wiggle room for rounding
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 1e9);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);

            if (noBaseYield && noCrvYield && !hasRewards) {
                assertGe(
                    asset.balanceOf(user) + 1, // 1 wei loss for 4626 rounding
                    balanceBefore + _amount,
                    "!final balance"
                );
            } else {
                assertGe(
                    asset.balanceOf(user),
                    balanceBefore + _amount,
                    "!final balance"
                );
            }
        }
    }

    // test a fixed deposit amount so we can see our logs, using trade factory for reward handling
    function test_operation_fixed() public {
        uint256 _amount = 10_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // make sure the gauge tokens are in the voter for curve strategy
        if (useConvex == false) {
            uint256 gaugeBalance = ERC20(strategy.gauge()).balanceOf(voter);
            assertGt(gaugeBalance, 0, "!gaugeVoter");
        }

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // simulate checking our strategy for CRV and reward tokens using trade factory
        // there will be no claimed rewards here since we haven't reported and/or claimed yet
        uint256 simulatedProfit = _amount / 200; // 0.5% profit
        simulateTradeFactory(simulatedProfit);

        // turn off health check if no yield since we may lose 1 wei from rounding
        if (noBaseYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log(
            "Profit from basic report:",
            profit / 1e18,
            "* 1e18 crvUSD"
        );
        uint256 roughApr = (((profit * 365) /
            (strategy.profitMaxUnlockTime() / 86400)) * 10_000) / _amount;
        console2.log("Rough APR from basic report:", roughApr, "BPS");
        console2.log(
            "Days to unlock profit:",
            strategy.profitMaxUnlockTime() / 86400
        );

        // Check return Values
        if (noBaseYield) {
            assertGe(profit, 0, "!profit");
            assertLe(loss, 1, "!loss");
        } else {
            assertGt(profit, 0, "!profit");
            assertEq(loss, 0, "!loss");
        }

        // force a claim of CRV and/or our other rewards
        skip(strategy.profitMaxUnlockTime());
        vm.prank(management);

        // after manually claiming rewards we have 2 days worth of CRV (or other token, uWu) rewards in our strategy
        strategy.claimRewards();
        simulateTradeFactory(simulatedProfit);

        // Report profit
        vm.prank(keeper);
        (uint256 profitTwo, uint256 lossTwo) = strategy.report();
        console2.log(
            "Profit from fancy report:",
            profitTwo / 1e18,
            "* 1e18 crvUSD"
        );

        if (noCrvYield && !hasRewards) {
            assertApproxEqAbs(profitTwo, profit, 1, "!profitComp");
            if (noBaseYield) {
                assertGe(profitTwo, 0, "!profit");
                assertLe(lossTwo, 1, "!loss");
            } else {
                assertGt(profitTwo, 0, "!profit");
                assertEq(lossTwo, 0, "!loss");
            }
        } else {
            if (useConvex) {
                (, uint256 cvxApr, ) = convexOracle.getConvexApr(
                    address(strategy),
                    strategy.vault(),
                    0
                );
                if (cvxApr == 0) {
                    assertGe(profitTwo, profit, "!profitComp");
                } else {
                    assertGt(profitTwo, profit, "!profitComp");
                }
            } else {
                assertGt(profitTwo, profit, "!profitComp");
            }
            assertGt(profitTwo, 0, "!profit");
            assertEq(lossTwo, 0, "!loss");
        }

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");
            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            vm.prank(user);
            strategy.withdraw(userToWithdraw, user, user);

            // check and make sure that our user still holds some amount of strategy tokens
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / 1e36;
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                1e36;
            // these should be equal, but give 1e9 wei of wiggle room for rounding
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 1e9);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);

            if (noBaseYield && noCrvYield && !hasRewards) {
                assertGe(
                    asset.balanceOf(user) + 1, // 1 wei loss for 4626 rounding
                    balanceBefore + _amount,
                    "!final balance"
                );
            } else {
                assertGe(
                    asset.balanceOf(user),
                    balanceBefore + _amount,
                    "!final balance"
                );
            }
        }
    }

    // fixed deposit using trade factory and at max util on curve lend
    function test_operation_max_util_fixed() public {
        uint256 _amount = 10_000e18;

        // whale causes max util
        bool isMaxUtil = causeMaxUtil();
        if (!isMaxUtil) {
            console2.log("Skip test, not max util for this market");
            return;
        }

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // make sure the gauge tokens are in the voter for curve strategy
        if (useConvex == false) {
            uint256 gaugeBalance = ERC20(strategy.gauge()).balanceOf(voter);
            assertGt(gaugeBalance, 0, "!gaugeVoter");
        }

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // simulate checking our strategy for CRV and reward tokens using trade factory
        // there will be no claimed rewards here since we haven't reported and/or claimed yet
        uint256 simulatedProfit = _amount / 200; // 0.5% profit
        simulateTradeFactory(simulatedProfit);

        // turn off health check if no yield since we may lose 1 wei from rounding
        if (noBaseYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log(
            "Profit from basic report:",
            profit / 1e18,
            "* 1e18 crvUSD"
        );
        uint256 roughApr = (((profit * 365) /
            (strategy.profitMaxUnlockTime() / 86400)) * 10_000) / _amount;
        console2.log("Rough APR from basic report:", roughApr, "BPS");
        console2.log(
            "Days to unlock profit:",
            strategy.profitMaxUnlockTime() / 86400
        );

        // Check return Values
        if (noBaseYield) {
            assertGe(profit, 0, "!profit");
            assertLe(loss, 1, "!loss");
        } else {
            assertGt(profit, 0, "!profit");
            assertEq(loss, 0, "!loss");
        }

        // force a claim of CRV and/or our other rewards
        skip(strategy.profitMaxUnlockTime());
        vm.prank(management);

        // after manually claiming rewards we have 2 days worth of CRV rewards in our strategy
        strategy.claimRewards();
        simulateTradeFactory(simulatedProfit);

        // Report profit
        vm.prank(keeper);
        (uint256 profitTwo, uint256 lossTwo) = strategy.report();
        console2.log(
            "Profit from fancy report:",
            profitTwo / 1e18,
            "* 1e18 crvUSD"
        );

        if (noCrvYield && !hasRewards) {
            assertEq(profitTwo, profit, "!profitComp");
            if (noBaseYield) {
                assertGe(profitTwo, 0, "!profit");
                assertLe(lossTwo, 1, "!loss");
            } else {
                assertGt(profitTwo, 0, "!profit");
                assertEq(lossTwo, 0, "!loss");
            }
        } else {
            if (useConvex) {
                (, uint256 cvxApr, ) = convexOracle.getConvexApr(
                    address(strategy),
                    strategy.vault(),
                    0
                );
                if (cvxApr == 0) {
                    assertGe(profitTwo, profit, "!profitComp");
                } else {
                    assertGt(profitTwo, profit, "!profitComp");
                }
            } else {
                assertGt(profitTwo, profit, "!profitComp");
            }
            assertGt(profitTwo, 0, "!profit");
            assertEq(lossTwo, 0, "!loss");
        }

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");

            // make sure we revert when we try and redeem locked funds
            vm.prank(user);
            vm.expectRevert("ERC4626: redeem more than max");
            strategy.redeem(_amount, user, user);

            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            if (userToWithdraw > 0) {
                vm.prank(user);
                strategy.withdraw(userToWithdraw, user, user);
            }

            // since our whale maxed out the market prior to us depositing, the only thing we won't be able to withdraw
            //  will be earned interest

            // check and make sure that our user still holds some amount of strategy tokens
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / 1e36;
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                1e36;
            // these should be equal, but give 10_000 wei of wiggle room for rounding
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 10_000);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);

            if (noBaseYield && noCrvYield && !hasRewards) {
                assertGe(
                    asset.balanceOf(user) + 1, // 1 wei loss for 4626 rounding
                    balanceBefore + _amount,
                    "!final balance"
                );
            } else {
                assertGe(
                    asset.balanceOf(user),
                    balanceBefore + _amount,
                    "!final balance"
                );
            }
        }
    }

    // test our atomic swaps instead of just airdropping in profit via trade factory
    function test_operation_atomic_fixed() public {
        uint256 _amount = 10_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // make sure the gauge tokens are in the voter for curve strategy
        if (useConvex == false) {
            uint256 gaugeBalance = ERC20(strategy.gauge()).balanceOf(voter);
            assertGt(gaugeBalance, 0, "!gaugeVoter");
        }

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // turn off health check if no yield since we may lose 1 wei from rounding
        if (noBaseYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log(
            "Profit from basic report:",
            profit / 1e18,
            "* 1e18 crvUSD"
        );
        uint256 roughApr = (((profit * 365) /
            (strategy.profitMaxUnlockTime() / 86400)) * 10_000) / _amount;
        console2.log("Rough APR from basic report:", roughApr, "BPS");
        console2.log(
            "Days to unlock profit:",
            strategy.profitMaxUnlockTime() / 86400
        );

        // Check return Values
        if (noBaseYield) {
            assertGe(profit, 0, "!profit");
            assertLe(loss, 1, "!loss");
        } else {
            assertGt(profit, 0, "!profit");
            assertEq(loss, 0, "!loss");
        }

        // set our reward type to be different
        vm.prank(management);
        strategy.setSwapType(address(crv), IStrategyInterface.SwapType.TRICRV);

        // check require
        vm.prank(management);
        vm.expectRevert("!null");
        strategy.setSwapType(address(crv), IStrategyInterface.SwapType.NULL);

        // skip forward in time
        skip(strategy.profitMaxUnlockTime());

        // Report profit
        vm.prank(keeper);
        (uint256 profitTwo, uint256 lossTwo) = strategy.report();
        console2.log(
            "Profit from fancy report:",
            profitTwo / 1e18,
            "* 1e18 crvUSD"
        );

        if (noCrvYield && !hasRewards) {
            assertApproxEqAbs(profitTwo, profit, 1, "!profitComp");
            if (noBaseYield) {
                assertGe(profitTwo, 0, "!profit");
                assertLe(lossTwo, 1, "!loss");
            } else {
                assertGt(profitTwo, 0, "!profit");
                assertEq(lossTwo, 0, "!loss");
            }
        } else {
            if (useConvex) {
                (, uint256 cvxApr, ) = convexOracle.getConvexApr(
                    address(strategy),
                    strategy.vault(),
                    0
                );
                if (cvxApr == 0) {
                    assertGe(profitTwo, profit, "!profitComp");
                } else {
                    assertGt(profitTwo, profit, "!profitComp");
                }
            } else {
                // uWu won't have any meaningful differences in the atomic swap test, so skip it
                if (!hasRewards) {
                    assertGt(profitTwo, profit, "!profitComp");
                }
            }
            assertGt(profitTwo, 0, "!profit");
            assertEq(lossTwo, 0, "!loss");
        }

        // check that we have loose assets and then tend them
        assertGt(strategy.balanceOfAsset(), 0, "!assets");
        vm.prank(keeper);
        strategy.tend();
        assertEq(strategy.balanceOfAsset(), 0, "!zero");

        // skip forward in time
        skip(strategy.profitMaxUnlockTime());

        // set min amount to sell very high so we don't sell anything
        vm.prank(management);
        strategy.setMinAmountToSellMapping(address(crv), type(uint256).max);

        // report profit
        vm.prank(keeper);
        (uint256 profitThree, ) = strategy.report();
        console2.log(
            "Profit from min amount report:",
            profitThree / 1e18,
            "* 1e18 crvUSD"
        );

        // since profitTwo had CRV yield and profitThree didn't, profitTwo should always be greater than or equal
        assertGe(profitTwo, profitThree, "!profitComp");

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");
            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            vm.prank(user);
            strategy.withdraw(userToWithdraw, user, user);

            // check and make sure that our user still holds some amount of strategy tokens
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / 1e36;
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                1e36;
            // these should be equal, but give 1e9 wei of wiggle room for rounding
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 1e9);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);

            if (noBaseYield && noCrvYield && !hasRewards) {
                assertGe(
                    asset.balanceOf(user) + 1, // 1 wei loss for 4626 rounding
                    balanceBefore + _amount,
                    "!final balance"
                );
            } else {
                assertGe(
                    asset.balanceOf(user),
                    balanceBefore + _amount,
                    "!final balance"
                );
            }
        }

        if (!useConvex && !hasRewards) {
            // add convex as an extra token to test removal
            vm.startPrank(management);
            strategy.addRewardToken(
                address(cvx),
                IStrategyInterface.SwapType.TF
            );
            address[] memory setRewardTokens = strategy.getAllRewardTokens();
            assertEq(setRewardTokens.length, 2);

            // remove
            strategy.removeRewardToken(address(cvx));
            address[] memory newSetRewardTokens = strategy.getAllRewardTokens();
            assertEq(newSetRewardTokens.length, 1);

            assertEq(
                uint256(strategy.swapType(address(cvx))),
                uint256(IStrategyInterface.SwapType.NULL)
            );
            vm.stopPrank();
        }
    }

    // test max utilization w/ atomic swaps
    function test_operation_max_util_atomic_fixed() public {
        uint256 _amount = 10_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // whale causes max util
        bool isMaxUtil = causeMaxUtil();
        if (!isMaxUtil) {
            console2.log("Skip test, not max util for this market");
            return;
        }

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // turn off health check if no yield since we may lose 1 wei from rounding
        if (noBaseYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console2.log(
            "Profit from basic report:",
            profit / 1e18,
            "* 1e18 crvUSD"
        );
        uint256 roughApr = (((profit * 365) /
            (strategy.profitMaxUnlockTime() / 86400)) * 10_000) / _amount;
        console2.log("Rough APR from basic report:", roughApr, "BPS");
        console2.log(
            "Days to unlock profit:",
            strategy.profitMaxUnlockTime() / 86400
        );

        // Check return Values
        if (noBaseYield) {
            assertGe(profit, 0, "!profit");
            assertLe(loss, 1, "!loss");
        } else {
            assertGt(profit, 0, "!profit");
            assertEq(loss, 0, "!loss");
        }

        // set our reward type to be different
        vm.prank(management);
        strategy.setSwapType(address(crv), IStrategyInterface.SwapType.TRICRV);

        // skip forward in time
        skip(strategy.profitMaxUnlockTime());

        // Report profit
        vm.prank(keeper);
        (uint256 profitTwo, uint256 lossTwo) = strategy.report();
        console2.log(
            "Profit from fancy report:",
            profitTwo / 1e18,
            "* 1e18 crvUSD"
        );

        if (noCrvYield && !hasRewards) {
            assertEq(profitTwo, profit, "!profitComp");
            if (noBaseYield) {
                assertGe(profitTwo, 0, "!profit");
                assertLe(lossTwo, 1, "!loss");
            } else {
                assertGt(profitTwo, 0, "!profit");
                assertEq(lossTwo, 0, "!loss");
            }
        } else {
            if (useConvex) {
                (, uint256 cvxApr, ) = convexOracle.getConvexApr(
                    address(strategy),
                    strategy.vault(),
                    0
                );
                if (cvxApr == 0) {
                    assertGe(profitTwo, profit, "!profitComp");
                } else {
                    assertGt(profitTwo, profit, "!profitComp");
                }
            } else {
                assertGt(profitTwo, profit, "!profitComp");
            }
            assertGt(profitTwo, 0, "!profit");
            assertEq(lossTwo, 0, "!loss");
        }

        // fully unlock our profit
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");

            // make sure we revert when we try and redeem locked funds
            vm.prank(user);
            vm.expectRevert("ERC4626: redeem more than max");
            strategy.redeem(_amount, user, user);

            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            if (userToWithdraw > 0) {
                vm.prank(user);
                strategy.withdraw(userToWithdraw, user, user);
            }

            // the profits should be all that we can withdraw from the strategy since the whale pulled all else
            // however profits also include earned base yield, which can't be withdrawn. so profits must be > the
            // withdrawable amount
            uint256 profitSum = profitTwo + profit;
            assertGt(profitSum, userToWithdraw, "profitSum issue");
            assertGt(userToWithdraw, 0, "userToWithdraw issue");

            // check and make sure that our user still holds some amount of strategy tokens
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / 1e36;
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                1e36;
            // these should be equal, but give 10 wei of wiggle room for rounding
            // need less rounding error here than on the other max util since we can withdraw so little here
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 10);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);

            if (noBaseYield && noCrvYield && !hasRewards) {
                assertGe(
                    asset.balanceOf(user) + 1, // 1 wei loss for 4626 rounding
                    balanceBefore + _amount,
                    "!final balance"
                );
            } else {
                assertGe(
                    asset.balanceOf(user),
                    balanceBefore + _amount,
                    "!final balance"
                );
            }
        }
    }

    function test_profitableReport_NoFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // since our lender is default profitable, doing max 10_000 will revert w/ health check
        //  (more than 100% total profit). so do 9950 to give some buffer for the interest earned.
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, 9_950));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // make sure fees are set to zero
        setFees(0, 0);

        // Earn Interest
        skip(1 days);

        // confirm that our strategy is empty (all funds deployed)
        assertEq(asset.balanceOf(address(strategy)), 0, "!empty");

        // implement logic to simulate earning interest (airdrop profit)
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // confirm that we have our airdrop amount in our strategy loose
        assertEq(asset.balanceOf(address(strategy)), toAirdrop, "!airdrop");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return values
        if (noBaseYield) {
            // we can get 1 wei loss on no native yield thanks to 4626 rounding
            assertGe(profit + 1, toAirdrop, "!profit");
        } else {
            assertGt(profit, toAirdrop, "!profit");
        }
        assertEq(loss, 0, "!loss");

        // skip time to unlock any profit we've earned
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");
            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            vm.prank(user);
            strategy.withdraw(userToWithdraw, user, user);

            // check and make sure that our user still holds some amount of strategy tokens, and that these
            //  tokens are worth what they didn't withdraw, including any profits
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / 1e36;
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                1e36;
            // these should be equal, but give 1e9 wei of wiggle room for rounding
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 1e9);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);

            if (noBaseYield && noCrvYield && !hasRewards) {
                assertGe(
                    asset.balanceOf(user) + 1, // 1 wei loss for 4626 rounding
                    balanceBefore + _amount,
                    "!final balance"
                );
            } else {
                assertGe(
                    asset.balanceOf(user),
                    balanceBefore + _amount,
                    "!final balance"
                );
            }
        }
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // since our lender is default profitable, doing max 10_000 will revert w/ health check
        //  (more than 100% total profit). so do 9950 to give some buffer for the interest earned.
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, 9_950));

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // implement logic to simulate earning interest (airdrop profit)
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        if (
            profit < 100_000 &&
            strategy.balanceOfStake() == ERC20(strategy.vault()).totalSupply()
        ) {
            // Curve lend MIN_ASSETS is 10_000, so we need fees (10%) to be higher than that iff the vault makes up
            //  100% of the llama lend market. see comment near end of this test for more details
            return;
        }

        // Check return values
        if (noBaseYield) {
            // we can get 1 wei loss on no native yield thanks to 4626 rounding
            assertGe(profit + 1, toAirdrop, "!profit");
        } else {
            assertGt(profit, toAirdrop, "!profit");
        }
        assertEq(loss, 0, "!loss");

        // skip time to unlock any profit we've earned
        skip(strategy.profitMaxUnlockTime());
        uint256 balanceBefore = asset.balanceOf(user);

        // Get the expected fee earned
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;
        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");
            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            vm.prank(user);
            strategy.withdraw(userToWithdraw, user, user);

            // check and make sure that our user still holds some amount of strategy tokens, and that these
            //  tokens are worth what they didn't withdraw, including any profits
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / 1e36;
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                1e36;
            // these should be equal, but give 1e9 wei of wiggle room for rounding
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 1e9);
        } else {
            // Withdraw all funds
            // ******** NOTE THAT THIS WILL FAIL IN A PREVIOUSLY EMPTY MARKET WITH FEES ON WHEN PROFITS ARE TAKEN
            // in llama lend vault, there is a MIN_ASSETS. you must either burn all shares (withdraw all assets),
            //  or make sure that the MIN_ASSETS is still left in the vault. w/ low assets/profits (fuzzing) the value
            //  may not enough to keep us above MIN_ASSETS. so for this test to always pass, make sure fees
            //  taken will be above MIN_ASSETS. really this is only a concern when depositing into an empty market.
            vm.prank(user);
            strategy.redeem(_amount, user, user);

            if (noBaseYield && noCrvYield && !hasRewards) {
                assertGe(
                    asset.balanceOf(user) + 1, // 1 wei loss for 4626 rounding
                    balanceBefore + _amount,
                    "!final balance"
                );
            } else {
                assertGe(
                    asset.balanceOf(user),
                    balanceBefore + _amount,
                    "!final balance"
                );
            }
        }

        // check if we're at full utilization for perf fee recipient
        if (
            strategy.maxWithdraw(performanceFeeRecipient) >
            strategy.totalAssets()
        ) {
            vm.prank(performanceFeeRecipient);
            strategy.redeem(
                expectedShares,
                performanceFeeRecipient,
                performanceFeeRecipient
            );
            checkStrategyTotals(strategy, 0, 0, 0);
            assertGe(
                asset.balanceOf(performanceFeeRecipient),
                expectedShares,
                "!perf fee out"
            );
        }
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // turn off health check if no yield since we may lose 1 wei from rounding
        if (noBaseYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        // report profit
        vm.prank(keeper);
        (, uint256 loss) = strategy.report();

        if (noBaseYield) {
            assertLe(loss, 1, "!loss");
        }

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");
            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            vm.prank(user);
            strategy.withdraw(userToWithdraw, user, user);

            // check and make sure that our user still holds some amount of strategy tokens, and that these
            //  tokens are worth what they didn't withdraw, including any profits
            uint256 totalUserShare = (_amount *
                1e18 *
                strategy.pricePerShare()) / 1e36;
            uint256 recreatedUserShare = userToWithdraw +
                (strategy.balanceOf(user) * 1e18 * strategy.pricePerShare()) /
                1e36;
            // these should be equal, but give 1e9 wei of wiggle room for rounding
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 1e9);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }

    // test other assorted setters
    function test_setters() public {
        // set min out bps
        vm.startPrank(management);
        vm.expectRevert("not bps");
        strategy.setMinOutBps(10_001);
        vm.expectRevert("10% max");
        strategy.setMinOutBps(5_000);
        strategy.setMinOutBps(9700);
        vm.stopPrank();
    }

    // test auction stuff
    function test_auction() public {
        // deploy a correct auction contract
        vm.startPrank(management);
        Auction correctAuction = new Auction();

        // init the auction contract with gud params
        correctAuction.initialize(
            address(asset),
            address(strategy),
            management,
            86400,
            1_000_000
        );

        // add this auction to our strategy
        strategy.setAuction(address(correctAuction));

        // set CRV as an auction asset
        strategy.setSwapType(address(crv), IStrategyInterface.SwapType.AUCTION);

        // enable CRV on the auction contract
        correctAuction.enable(address(crv));

        // will kick w/ zero assets but should revert in the auction itself
        vm.expectRevert("nothing to kick");
        strategy.kickAuction(address(crv));

        // add vault token to the auction itself (can't add want with a proper auction contract)
        correctAuction.enable(curveLendVault);
        vm.expectRevert("ZERO ADDRESS");
        correctAuction.enable(address(asset));

        // try and kick the auction, will fail since it's not added as an auction reward token
        // and will also revert if we try to add it as a reward token since it's the vault
        vm.expectRevert("!auction");
        strategy.kickAuction(curveLendVault);

        // deploy more auctions!
        Auction wrongAuction = new Auction();

        // init the auction contract with wrong recipient
        wrongAuction.initialize(
            address(asset),
            management, // this should be the strategy
            management,
            86400,
            1_000_000
        );
        vm.expectRevert("wrong receiver");
        strategy.setAuction(address(wrongAuction));

        // deploy more auctions!
        wrongAuction = new Auction();

        // init the auction contract with wrong want
        wrongAuction.initialize(
            address(crv), // this should be asset()
            address(strategy),
            management,
            86400,
            1_000_000
        );
        vm.expectRevert("wrong want");
        strategy.setAuction(address(wrongAuction));
    }
}

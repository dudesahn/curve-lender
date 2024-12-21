// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

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

    function test_operation_fuzzy(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Report profit
        if (noYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        if (noYield) {
            assertLe(loss, 1, "!loss");
        } else {
            assertEq(loss, 0, "!loss");
        }

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
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
            // if _amount is too low, we may have issues with rounding here
            if (_amount > minAprOracleFuzzAmount) {
                assertApproxEqAbs(
                    totalUserShare,
                    recreatedUserShare,
                    minAprOracleFuzzAmount
                );
            }
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        if (noYield) {
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

    function test_operation_fixed() public {
        uint256 _amount = 10_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // make sure the gauge tokens are in the voter for curve strategy
        if (useConvex == false) {
            uint256 gaugeBalance = ERC20(strategy.gauge()).balanceOf(voter);
            assertGt(gaugeBalance, 0, "!gaugeVoter");
        }

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(strategy.profitMaxUnlockTime());

        // simulate checking our strategy for CRV and reward tokens using trade factory
        // should be no tokens to claim since we don't have the logic auto-claiming during reports
        uint256 simulatedProfit = _amount / 200; // 0.5% profit
        simulateTradeFactory(simulatedProfit);

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
        if (noYield) {
            assertGe(profit, 0, "!profit");
            assertLe(loss, 1, "!loss");
        } else {
            assertGt(profit, 0, "!profit");
            assertEq(loss, 0, "!loss");
        }

        // force a claim of CRV and/or our other rewards
        skip(strategy.profitMaxUnlockTime());
        vm.prank(management);
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

        // technically we should probably check first if we even have CRV rewards before doing this comparison, but whatever
        if (noYield) {
            assertGe(profitTwo + 1, profit, "!profitComp");
            assertGe(profitTwo, 0, "!profit");
            assertLe(lossTwo, 1, "!loss");
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
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 1e18);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        if (noYield) {
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

        // Earn Interest
        skip(1 days);

        // confirm that our strategy is empty
        assertEq(asset.balanceOf(address(strategy)), 0, "!empty");

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // confirm that we have our airdrop amount in our strategy loose
        assertEq(asset.balanceOf(address(strategy)), toAirdrop, "!airdrop");

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        if (
            profit < 100_000 &&
            strategy.balanceOfStake() == ERC20(strategy.vault()).totalSupply()
        ) {
            // MIN_ASSETS is 10_000, so we need fees (10%) to be higher than that
            return;
        }

        // Check return Values
        if (noYield) {
            assertGe(profit + 1, toAirdrop, "!profit"); // we can get 1 wei loss on no native yield thanks to 4626
        } else {
            assertGt(profit, toAirdrop, "!profit");
        }
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
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
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 1e18);
        } else {
            // Withdraw all funds
            // ******** NOTE THAT THIS WILL FAIL WITH AN EMPTY MARKET (AND IN NEXT TEST)
            // ***** HAS TO DO WITH THERE BEING PROFITS FROM AIRDROP
            // in llama lend vault, there is a MIN_ASSETS. you must either burn all shares (withdraw all assets),
            //  or make sure that the MIN_ASSETS is still left in the vault. w/ low assets/profits (fuzzing) the value
            //  may not enough to keep us above MIN_ASSETS. so for this test to always pass, make sure fees
            //  taken will be above MIN_ASSETS. really this is only a concern when depositing into an empty market
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        assertGt(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
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

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        if (
            profit < 100_000 &&
            strategy.balanceOfStake() == ERC20(strategy.vault()).totalSupply()
        ) {
            // MIN_ASSETS is 10_000, so we need fees (10%) to be higher than that
            // see comment in previous test for more details
            return;
        }

        // Check return Values
        if (noYield) {
            assertGe(profit + 1, toAirdrop, "!profit"); // we can get 1 wei loss on no native yield thanks to 4626
        } else {
            assertGt(profit, toAirdrop, "!profit");
        }
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
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
            assertApproxEqAbs(totalUserShare, recreatedUserShare, 1e18);
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        assertGt(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );

        // check if we're at full utilization
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

        // Report profit
        if (noYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);
        }

        vm.prank(keeper);
        (, uint256 loss) = strategy.report();

        if (noYield) {
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
            // if _amount is too low, we may have issues with rounding here
            if (_amount > minAprOracleFuzzAmount) {
                assertApproxEqAbs(
                    totalUserShare,
                    recreatedUserShare,
                    minAprOracleFuzzAmount
                );
            }
        } else {
            // Withdraw all funds
            vm.prank(user);
            strategy.redeem(_amount, user, user);
        }

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }
}

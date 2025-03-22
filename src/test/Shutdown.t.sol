pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        uint256 toRedeem = strategy.maxRedeem(user);

        if (noYield) {
            vm.prank(user);
            strategy.redeem(toRedeem, user, user);
            assertLe(strategy.totalAssets(), 1, "!one");
        } else {
            vm.prank(user);
            strategy.redeem(_amount, user, user);
            assertEq(strategy.totalAssets(), 0, "!zero");
        }

        assertGe(
            asset.balanceOf(user) + 1, // add a 1 wei buffer since we convert between shares on deposit/withdraw
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_shutdown_MaxUint() public {
        uint256 _amount = 1_000_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        // assets shouldn't have gone anywhere
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // balance of assets should be zero in strategy still
        assertEq(strategy.balanceOfAsset(), 0, "!assets");

        // value of vault should be positive
        uint256 valueOfVault = strategy.valueOfVault();
        assertGt(valueOfVault, 0, "!value");
        console2.log("Value of vault tokens:", valueOfVault, "crvUSD");

        // management steps in to get funds out ASAP
        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        // balance of assets should be greater than zero now
        uint256 balanceOfAssets = strategy.balanceOfAsset();
        assertGt(balanceOfAssets, 0, "!assets");
        console2.log("Balance of loose assets:", balanceOfAssets, "crvUSD");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(strategy.totalAssets(), 0, "!zero");

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

    function test_max_util_shutdown_MaxUint() public {
        uint256 _amount = 1_000_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // whale causes max util
        bool isMaxUtil = causeMaxUtil();
        if (!isMaxUtil) {
            console2.log("Skip test, not max util for this market");
            return;
        }

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        // assets shouldn't have gone anywhere
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // balance of assets should be zero in strategy still
        assertEq(strategy.balanceOfAsset(), 0, "!assets");

        // value of vault should be positive
        uint256 valueOfVault = strategy.valueOfVault();
        assertGt(valueOfVault, 0, "!value");
        console2.log("Value of vault tokens:", valueOfVault, "crvUSD");

        // management steps in to get funds out ASAP
        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        // balance of assets should be greater than zero now
        uint256 balanceOfAssets = strategy.balanceOfAsset();
        console2.log("Balance of loose assets:", balanceOfAssets, "crvUSD");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // ***SINCE WE HAVEN'T HAD ANY PROFIT, WILL BE TRYING TO WITHDRAW/REDEEM ZERO
        // check on other one that total redemption is just sum of profits

        // check if we're at full utilization
        if (strategy.totalAssets() > strategy.availableWithdrawLimit(user)) {
            console2.log("Can't withdraw all funds");
            // Withdraw all funds, or at least as much as we expect to be free
            // make sure to use maxWithdraw for our users, NOT availableWithdrawLimit
            // the latter is for the whole vault, not by user
            uint256 userToWithdraw = strategy.maxWithdraw(user);
            if (userToWithdraw > 0) {
                vm.prank(user);
                strategy.withdraw(userToWithdraw, user, user);
            }

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

            assertEq(strategy.totalAssets(), 0, "!zero");

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
    }
}

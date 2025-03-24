pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    // make sure user can withdraw from a shutdown strategy
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

        if (noBaseYield) {
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

    // make sure passing max uint should work when withdrawing in a shutdown strategy
    function test_shutdown_MaxUint() public {
        uint256 _amount = 1_000_000e18;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // turn off health check if no yield since we may lose 1 wei from rounding
        if (noBaseYield) {
            vm.prank(management);
            strategy.setDoHealthCheck(false);

            // report so we can accept rounding loss from deposit
            vm.prank(keeper);
            strategy.report();
        }

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        // assets shouldn't have gone anywhere
        if (noBaseYield) {
            assertEq(strategy.totalAssets() + 1, _amount, "!totalAssets");
        } else {
            assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        }

        // balance of assets should be zero in strategy still
        assertEq(strategy.balanceOfAsset(), 0, "!assets");

        // check our withdraw limit
        console2.log(
            "Available withdrawal limit:",
            strategy.availableWithdrawLimit(user),
            "crvUSD"
        );

        // convert the amount to withdraw from shares to assets
        console2.log(
            "Shares to assets:",
            IStrategyInterface(strategy.vault()).convertToAssets(
                strategy.balanceOfStake()
            ),
            "crvUSD"
        );

        // pre-shutdown vault token balance
        console2.log(
            "Balance of vault before shutdown:",
            strategy.balanceOfVault(),
            "crvUSD"
        );
        console2.log(
            "Balance of stake before shutdown:",
            strategy.balanceOfStake(),
            "crvUSD"
        );
        console2.log(
            "Before shutdown max withdraw:",
            strategy.vaultsMaxWithdraw(),
            "crvUSD"
        );

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
        console2.log(
            "Balance of loose assets after shutdown:",
            balanceOfAssets,
            "crvUSD"
        );

        // vault token balance
        console2.log(
            "Balance of vault after shutdown:",
            strategy.balanceOfVault(),
            "crvUSD"
        );
        console2.log(
            "Balance of stake after shutdown:",
            strategy.balanceOfStake(),
            "crvUSD"
        );
        console2.log(
            "After shutdown max withdraw:",
            strategy.vaultsMaxWithdraw(),
            "crvUSD"
        );
        console2.log(
            "After shutdown available withdrawal limit:",
            strategy.availableWithdrawLimit(user),
            "crvUSD"
        );

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // comment out this block because we don't need to airdrop as long as we report above, but it is another option
        // check withdraw limit, if it's below, then airdrop one wei (crvUSD vault rounding issues)
        //         if (strategy.availableWithdrawLimit(user) < _amount && noBaseYield) {
        //             // airdrop one wei of crvUSD to the strategy
        //             airdrop(asset, address(strategy), 1);
        //
        //             console2.log(
        //                 "After airdrop available withdrawal limit:",
        //                 strategy.availableWithdrawLimit(user),
        //                 "crvUSD"
        //             );
        //         }

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(strategy.totalAssets(), 0, "!zero");

        if (noBaseYield) {
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
        console2.log("User balance:", asset.balanceOf(user));
    }

    function test_max_util_after_deposit_shutdown_MaxUint() public {
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
        console2.log(
            "Balance of loose vault token:",
            strategy.balanceOfVault()
        );
        console2.log(
            "Balance of staked vault tokens:",
            strategy.balanceOfStake()
        );

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

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

            // since we haven't had any profit, we will be trying to withdraw/redeem zero

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

            assertEq(strategy.totalAssets(), 0, "!zero");

            if (noBaseYield) {
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

    function test_max_util_before_deposit_shutdown_MaxUint() public {
        uint256 _amount = 1_000_000e18;

        // whale causes max util
        bool isMaxUtil = causeMaxUtil();
        if (!isMaxUtil) {
            console2.log("Skip test, not max util for this market");
            return;
        }

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, ) = strategy.report();

        // skip time to unlock any profit we've earned
        skip(strategy.profitMaxUnlockTime());

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        // assets shouldn't have gone anywhere
        assertEq(strategy.totalAssets(), _amount + profit, "!totalAssets");

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
        console2.log(
            "Balance of loose vault token:",
            strategy.balanceOfVault()
        );
        console2.log(
            "Balance of staked vault tokens:",
            strategy.balanceOfStake()
        );

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

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

            // we should be able to withdraw everything but our profits

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

            assertEq(strategy.totalAssets(), 0, "!zero");

            if (noBaseYield) {
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

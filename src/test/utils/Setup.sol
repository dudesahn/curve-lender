// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {StrategyCrvusdRouter, ERC20} from "../../StrategyCrvusdRouter.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IV2StrategyInterface} from "../../interfaces/IV2StrategyInterface.sol";
import {ICurveStrategyProxy} from "../../interfaces/ICrvusdInterfaces.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public constant chad = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    // addresses for deployment
    address public curveLendVault;
    address public curveLendGauge;

    // yearn's strategy proxy and voter
    ICurveStrategyProxy public constant strategyProxy =
        ICurveStrategyProxy(0x78eDcb307AC1d1F8F5Fd070B377A6e69C8dcFC34);
    address public constant voter = 0xF147b8125d2ef93FB6965Db97D6746952a133934;

    // trade factory and rewards stuff
    address public constant tradeFactory =
        0xb634316E06cC0B358437CbadD4dC94F1D3a92B3b;
    bool public hasRewards; // bool for if a gauge has extra rewards we need to claim
    address public rewardToken;
    ERC20 public constant crv =
        ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 1e4;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 1 days;

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["crvUSD"]);

        // Set decimals
        decimals = asset.decimals();

        // set market/gauge variables
        uint256 useMarket = 0;

        if (useMarket == 0) {
            // wstETH
            curveLendVault = 0x21CF1c5Dc48C603b89907FE6a7AE83EA5e3709aF;
            curveLendGauge = 0x0621982CdA4fD4041964e91AF4080583C5F099e1;

            // need special logic here to shutdown the existing vault
            IV2StrategyInterface vaultV2 = IV2StrategyInterface(
                0xbA8e83CC28B54bB063984033Df20F9a9F1220C24
            );
            IV2StrategyInterface strategyV2 = IV2StrategyInterface(
                vaultV2.withdrawalQueue(1)
            );

            // we have to clear this out before we set associate our new strategy with the gauge
            vm.startPrank(chad);
            vaultV2.updateStrategyDebtRatio(address(strategyV2), 0);
            strategyV2.harvest();
            vm.stopPrank();
        } else if (useMarket == 1) {
            // sDOLA (should not revert)
            curveLendVault = 0x14361C243174794E2207296a6AD59bb0Dec1d388;
            curveLendGauge = 0x30e06CADFbC54d61B7821dC1e58026bf3435d2Fe;
        } else if (useMarket == 2) {
            // UwU (use to test gauges with extra incentives)
            curveLendVault = 0x7586C58bf6292B3C9DeFC8333fc757d6c5dA0f7E;
            curveLendGauge = 0xad7B288315b0d71D62827338251A8D89A98132A0;
            hasRewards = true;
            rewardToken = 0x55C08ca52497e2f1534B59E2917BF524D4765257;
        } else if (useMarket == 3) {
            // sUSDe (vault exists for it, but is empty, so nothing else needed to do)
            curveLendVault = 0x4a7999c55d3a93dAf72EA112985e57c2E3b9e95D;
            curveLendGauge = 0xAE1680Ef5EFc2486E73D8d5D0f8a8dB77DA5774E;
        }

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());
        factory = strategy.FACTORY();

        // setup trade factory
        setUpTradeFactory();

        // add our new strategy to the voter proxy
        setUpProxy();

        // label all the used addresses for traces
        vm.label(user, "user");
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(chad, "ychad");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                new StrategyCrvusdRouter(
                    address(asset),
                    "Curve Boosted crvUSD-sDOLA Lender",
                    curveLendVault,
                    curveLendGauge,
                    address(strategyProxy)
                )
            )
        );

        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);
        // set profit unlock
        _strategy.setProfitMaxUnlockTime(profitMaxUnlockTime);

        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }

    function setUpTradeFactory() public {
        vm.prank(management);
        strategy.setTradeFactory(tradeFactory);
        vm.prank(management);
        strategy.addToken(address(crv));
        if (hasRewards) {
            // add our rewards token to our strategy if needed
            vm.prank(management);
            strategy.addToken(rewardToken);
        }
    }

    function setUpProxy() public {
        // approve reward token on our strategy proxy if needed
        if (hasRewards) {
            // shouldn't need this for non-legacy gauges
            // vm.prank(chad);
            // strategyProxy.approveRewardToken(rewardToken, true);
        }

        // approve our new strategy on the proxy (if we want to test an existing want, a bit more work is needed)
        //if strategyProxy.strategies(strategy.gauge()) != address(0) {
        //    // revoke strategy on gauge
        //    strategyProxy.revokeStrategy(strategy.gauge(), sender=gov)
        // }
        //empty out our voter if it holds gauge tokens
        //if gauge.balanceOf(voter) > 0:
        //    gauge.transfer(ZERO_ADDRESS, gauge.balanceOf(voter), sender=voter)
        //    assert gauge.balanceOf(voter) == 0

        // link the strategy and gauge on the strategy proxy
        vm.startPrank(chad); // need to do start/stop since we pull the gauge via call
        strategyProxy.approveStrategy(strategy.gauge(), address(strategy));
        vm.stopPrank();
    }

    function simulateTradeFactory(uint256 _profitAmount) public {
        // check for reward token balance
        uint256 rewardBalance = 0;
        if (hasRewards) {
            // trade factory should sweep out rewards, and we mint the strategy _profitAmount of asset
            rewardBalance = ERC20(rewardToken).balanceOf(address(strategy));
        }

        // if we have reward tokens, sweep it out, and send back our designated profitAmount
        if (rewardBalance > 0) {
            console2.log(
                "Reward token sitting in our strategy",
                rewardBalance / 1e18,
                "* 1e18"
            );

            vm.prank(tradeFactory);
            ERC20(rewardToken).transferFrom(
                address(strategy),
                tradeFactory,
                rewardBalance
            );
            airdrop(asset, address(strategy), _profitAmount);
            rewardBalance = ERC20(rewardToken).balanceOf(address(strategy));
        }

        // trade factory should sweep out CRV, and we mint the strategy _profitAmount of asset
        uint256 crvBalance = crv.balanceOf(address(strategy));

        // if we have CRV, sweep it out, and send back our designated profitAmount
        if (crvBalance > 0) {
            console2.log(
                "CRV sitting in our strategy",
                crvBalance / 1e18,
                "* 1e18 CRV"
            );
            vm.prank(tradeFactory);
            crv.transferFrom(address(strategy), tradeFactory, crvBalance);
            airdrop(asset, address(strategy), _profitAmount);
            crvBalance = crv.balanceOf(address(strategy));
        }

        // confirm that we swept everything out
        assertEq(crvBalance, 0, "!crvBalance");
        assertEq(rewardBalance, 0, "!rewardBalance");
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenAddrs["crvUSD"] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    }
}

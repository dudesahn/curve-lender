// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

// contracts
import {StrategyLlamaLendCurve, ERC20} from "src/StrategyLlamaLendCurve.sol";
import {StrategyLlamaLendConvex} from "src/StrategyLlamaLendConvex.sol";
import {LlamaLendCurveFactory} from "src/LlamaLendCurveFactory.sol";
import {LlamaLendConvexFactory} from "src/LlamaLendConvexFactory.sol";
import {LlamaLendOracle} from "src/periphery/StrategyAprOracle.sol";
import {LlamaLendConvexOracle} from "src/periphery/StrategyAprOracleConvex.sol";

// interfaces
import {IStrategyInterface} from "src/interfaces/IStrategyInterface.sol";
import {IV2StrategyInterface} from "src/interfaces/IV2StrategyInterface.sol";
import {IProxy, IGauge, IVault, IController} from "src/interfaces/ICurveInterfaces.sol";
import {IConvexBooster, IConvexRewards} from "src/interfaces/IConvexInterfaces.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

// import auction so we can deploy a mock to test our auction functions
import {Auction} from "@periphery/Auctions/Auction.sol";

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
    address public constant emergencyAdmin =
        0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7; // sms

    // whether we test our curve or convex strategy
    bool public useConvex;

    // uint for which market we use
    uint256 public useMarket;

    // addresses for deployment
    address public curveLendVault;
    address public curveLendGauge;

    // factories
    LlamaLendCurveFactory public curveFactory;
    LlamaLendConvexFactory public convexFactory;

    // convex vars
    uint256 public pid;
    address public constant booster =
        0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    // yearn's strategy proxy and voter
    IProxy public constant strategyProxy =
        IProxy(0x78eDcb307AC1d1F8F5Fd070B377A6e69C8dcFC34);
    address public constant voter = 0xF147b8125d2ef93FB6965Db97D6746952a133934;

    // trade factory and rewards stuff
    address public constant tradeFactory =
        0xb634316E06cC0B358437CbadD4dC94F1D3a92B3b;
    bool public hasRewards; // bool for if a gauge has extra rewards we need to claim
    address public rewardToken;
    ERC20 public constant crv =
        ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public constant cvx =
        ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 1e6; // 1e4-1e5 fails profit tests at base interest rates
    uint256 public minAprOracleFuzzAmount = 1e18; // at tiny deposits, APR may not change enough to detect

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 1 days;

    // state vars to use in case we have very low or zero yield; some of our assumptions break
    bool public noBaseYield;
    bool public lowBaseYield;
    bool public noCrvYield;
    bool public emptyConvex;

    LlamaLendOracle public oracle;
    LlamaLendConvexOracle public convexOracle;

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["crvUSD"]);

        // Set decimals
        decimals = asset.decimals();

        /* ========== UPDATE THESE BELOW FOR TESTING ========== */

        // set market/gauge variables
        useMarket = 0;
        // 0: wstETH (passing, passing)
        // 1: sDOLA (passing, passing)
        // 2: uWu (extra rewards) (passing, passing)
        // 3: sUSDe (passing, passing)
        // 4: tBTC (passing, passing)
        // 5: USD0 (passing, no convex). 1 token borrowed, no meaningful base yield
        // 6: ynETH dead (passing, no convex). empty market.
        // 7: ynETH good (passing, passing). no meaningful base yield but CRV emissions.
        // 8: RCH (passing, no convex). No borrows

        useConvex = false;

        // do this if we want to test the empty convex market for uWu
        emptyConvex = false;

        /* ========== UPDATE THESE ABOVE FOR TESTING ========== */

        // deploy our strategy factories
        curveFactory = new LlamaLendCurveFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );
        convexFactory = new LlamaLendConvexFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );

        // give our factory the power to add strategy/gauges to strategy proxy
        // no harm in doing this even on convex strategies
        setUpProxy();

        if (useMarket == 0) {
            // wstETH
            curveLendVault = 0x21CF1c5Dc48C603b89907FE6a7AE83EA5e3709aF;
            curveLendGauge = 0x0621982CdA4fD4041964e91AF4080583C5F099e1;
            pid = 364;

            // since this curve vault has TVL, need a few special steps
            // trying to deploy this strategy now should revert
            vm.expectRevert("strategy exists");
            vm.prank(management);
            curveFactory.newCurveLender(
                "Curve Boosted crvUSD-sDOLA Lender",
                curveLendVault,
                curveLendGauge
            );

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
            // now we remove the strategy-gauge linkage on the strategy proxy
            strategyProxy.revokeStrategy(curveLendGauge);

            // now we expect the authorized revert
            vm.expectRevert("!authorized");
            curveFactory.newCurveLender(
                "Curve Boosted crvUSD-sDOLA Lender",
                curveLendVault,
                curveLendGauge
            );
            vm.stopPrank();
        } else if (useMarket == 1) {
            // sDOLA
            curveLendVault = 0x14361C243174794E2207296a6AD59bb0Dec1d388;
            curveLendGauge = 0x30e06CADFbC54d61B7821dC1e58026bf3435d2Fe;
            pid = 384;
        } else if (useMarket == 2) {
            // UwU (use to test gauges with extra incentives)
            curveLendVault = 0x7586C58bf6292B3C9DeFC8333fc757d6c5dA0f7E;
            curveLendGauge = 0xad7B288315b0d71D62827338251A8D89A98132A0;
            pid = 343;
            hasRewards = true;

            // uwu has old crv yield on convex...
            if (!useConvex) {
                noCrvYield = true;
            }

            rewardToken = 0x55C08ca52497e2f1534B59E2917BF524D4765257;

            // simulate sifu adding more rewards to the gauge
            address sifu = 0x5DD596C901987A2b28C38A9C1DfBf86fFFc15d77;
            IGauge uwuGauge = IGauge(curveLendGauge);
            vm.prank(sifu);
            uwuGauge.deposit_reward_token(rewardToken, 20_000e18);
        } else if (useMarket == 3) {
            // sUSDe (vault exists for it, but is empty, so just need to revoke)
            curveLendVault = 0x4a7999c55d3a93dAf72EA112985e57c2E3b9e95D;
            curveLendGauge = 0xAE1680Ef5EFc2486E73D8d5D0f8a8dB77DA5774E;
            pid = 361;

            // remove the strategy-gauge linkage on the strategy proxy
            vm.prank(chad);
            strategyProxy.revokeStrategy(curveLendGauge);
        } else if (useMarket == 4) {
            // tBTC (needs notify rewards on Convex!)
            curveLendVault = 0xb2b23C87a4B6d1b03Ba603F7C3EB9A81fDC0AAC9;
            curveLendGauge = 0x41eBf0bEC45642A675e8b7536A2cE9c078A814B4;
            pid = 328;

            // remove the strategy-gauge linkage on the strategy proxy
            vm.prank(chad);
            strategyProxy.revokeStrategy(curveLendGauge);
        } else if (useMarket == 5) {
            // USD0 (tiny TVL, 1 crvUSD borrowed, not approved on gauge controller). will revert for convex
            curveLendVault = 0x0111646E459e0BBa57daCA438262f3A092ae24C6;
            curveLendGauge = 0x1d701D23CE74d5B721d24D668A79c44Db2D5A0AE;
            lowBaseYield = true;
            noCrvYield = true;
        } else if (useMarket == 6) {
            // ynETH dead market (fully empty, not approved on gauge controller). will revert for convex
            curveLendVault = 0xC6F7E164ed085b68d5DF20d264f70410CB0B7458;
            curveLendGauge = 0xe9cA32785e192abD1bcF4e9fa0160Dc47E93ED89;
            noBaseYield = true;
            noCrvYield = true;
        } else if (useMarket == 7) {
            // ynETH good market
            curveLendVault = 0x52036c9046247C3358c987A2389FFDe6Ef8564c9;
            curveLendGauge = 0x8966A85b414620ef460DeEaCD821c30c442C433F;
            pid = 415;
            lowBaseYield = true;
        } else if (useMarket == 8) {
            // RCH, literally 0 borrows, 2k deposited, not on gauge controller
            curveLendVault = 0xc9cCB6E3Cc9D1766965278Bd1e7cc4e58549D1F8;
            curveLendGauge = 0x11C2a9fac65809c527bcb04FB7EC52080F053dc0;
            noBaseYield = true;
            noCrvYield = true;
        }

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());
        factory = strategy.FACTORY();

        // setup trade factory
        setUpTradeFactory();

        // do this if we want to test the empty convex market
        if (useConvex && emptyConvex && useMarket == 2) {
            address uwu_depositor = 0xabeaE2f19BD2cA5408E050F7498b098ad34b2b26;
            IConvexRewards rewardsContract = IConvexRewards(
                strategy.rewardsContract()
            );
            uint256 toWithdraw = rewardsContract.totalSupply();
            vm.prank(uwu_depositor);
            rewardsContract.withdrawAndUnwrap(toWithdraw, true);
            assertEq(0, rewardsContract.totalSupply(), "!empty");
        }

        // add our new strategy to the voter proxy
        if (useConvex == false) {
            // setup rewards claiming
            if (useMarket == 0) {
                // wstETH
                vm.prank(management);
                strategy.setClaimFlags(true, false);
            } else if (useMarket == 1) {
                // sDOLA
                vm.prank(management);
                strategy.setClaimFlags(true, false);
            } else if (useMarket == 2) {
                // UwU (use to test gauges with extra incentives). approved on gauge controller but no emissions currently
                vm.prank(management);
                strategy.setClaimFlags(false, true);
            } else if (useMarket == 3) {
                // sUSDe (vault exists for it, but is empty, so nothing else needed to do)
                vm.prank(management);
                strategy.setClaimFlags(true, false);
            } else if (useMarket == 4) {
                // tBTC
                vm.prank(management);
                strategy.setClaimFlags(true, false);
            } else if (useMarket == 5) {
                // USD0 (tiny TVL, not approved on gauge controller)
                vm.prank(management);
                strategy.setClaimFlags(false, false);
            } else if (useMarket == 6) {
                // ynETH (fully empty, not approved on gauge controller)
                vm.prank(management);
                strategy.setClaimFlags(false, false);
            } else if (useMarket == 7) {
                // ynETH good market
                vm.prank(management);
                strategy.setClaimFlags(true, false);
            } else if (useMarket == 8) {
                // RCH no borrows, not approved
                vm.prank(management);
                strategy.setClaimFlags(false, false);
            }
        } else {
            // check if there is any CRV we need to earmark
            IConvexRewards rewardsContract = IConvexRewards(
                strategy.rewardsContract()
            );
            uint256 crvExpiry = rewardsContract.periodFinish();
            // important to only earmark when needed or else convex booster will revert
            if (crvExpiry < block.timestamp) {
                IConvexBooster(booster).earmarkRewards(pid);
            }
        }

        // deploy our oracles
        oracle = new LlamaLendOracle();
        convexOracle = new LlamaLendConvexOracle();

        // label all the used addresses for traces
        vm.label(user, "user");
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(chad, "ychad");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(emergencyAdmin, "SMS");
    }

    function causeMaxUtil() public returns (bool isMaxUtil) {
        IController controller = IController(
            IVault(strategy.vault()).controller()
        );
        if (useMarket == 0 || useMarket == 3 || useMarket == 4) {
            address whale;
            if (useMarket == 0) {
                // wstETH
                whale = 0xd85351181b3F264ee0FDFa94518464d7c3DefaDa;
            } else if (useMarket == 3) {
                // sUSDe
                whale = 0xE877B2A8a53763C8B0534a15e87da28f3aC1257e;
            } else if (useMarket == 4) {
                // tbtc
                whale = 0xF8aaE8D5dd1d7697a4eC6F561737e68a2ab8539e;
            }
            ERC20 collateral_token = ERC20(controller.collateral_token());
            vm.startPrank(whale);
            collateral_token.approve(address(controller), type(uint256).max);
            // will get revert: Amount too low if whale doesn't have enough here
            controller.create_loan(
                collateral_token.balanceOf(whale),
                asset.balanceOf(address(controller)),
                50
            ); // 50 bands
            vm.stopPrank();
            console2.log("Pushed market to max utilization");
            isMaxUtil = true;
        }
    }

    function setUpStrategy() public returns (address) {
        IStrategyInterface _strategy;
        if (useConvex) {
            // we save the strategy as a IStrategyInterface to give it the needed interface
            vm.prank(management);
            _strategy = IStrategyInterface(
                convexFactory.newConvexLender(
                    "Convex crvUSD-sDOLA Lender",
                    curveLendVault,
                    pid
                )
            );
            assertEq(_strategy.management(), address(convexFactory));
        } else {
            // don't deploy with the wrong gauge
            vm.prank(management);
            vm.expectRevert("gauge mismatch");
            curveFactory.newCurveLender(
                "Convex crvUSD-sDOLA Lender",
                0x0111646E459e0BBa57daCA438262f3A092ae24C6,
                0x30e06CADFbC54d61B7821dC1e58026bf3435d2Fe
            );

            // we save the strategy as a IStrategyInterface to give it the needed interface
            vm.prank(management);
            _strategy = IStrategyInterface(
                curveFactory.newCurveLender(
                    "Curve Boosted crvUSD-sDOLA Lender",
                    curveLendVault,
                    curveLendGauge
                )
            );
            assertEq(_strategy.management(), address(curveFactory));
        }

        vm.prank(management);
        _strategy.acceptManagement();

        // set profit unlock
        vm.prank(management);
        _strategy.setProfitMaxUnlockTime(profitMaxUnlockTime);

        return address(_strategy);
    }

    function setUpTradeFactory() public {
        vm.startPrank(management);
        strategy.setTradeFactory(tradeFactory);

        // add crv
        // shouldn't add with null
        vm.expectRevert("!null");
        strategy.addRewardToken(address(crv), IStrategyInterface.SwapType.NULL);

        // add for reals
        strategy.addRewardToken(address(crv), IStrategyInterface.SwapType.TF);

        // make sure our requires work
        vm.expectRevert("!exists");
        strategy.addRewardToken(
            address(crv),
            IStrategyInterface.SwapType.AUCTION
        );

        // can't add vault or asset
        vm.expectRevert("!allowed");
        strategy.addRewardToken(address(asset), IStrategyInterface.SwapType.TF);
        vm.expectRevert("!allowed");
        strategy.addRewardToken(curveLendVault, IStrategyInterface.SwapType.TF);

        if (useConvex) {
            strategy.addRewardToken(
                address(cvx),
                IStrategyInterface.SwapType.TF
            );
        }

        if (hasRewards) {
            // add our rewards token to our strategy if needed
            strategy.addRewardToken(
                rewardToken,
                IStrategyInterface.SwapType.TF
            );
        }
        vm.stopPrank();
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

        // approve our new factory to add gauge/strategy combos to strategy proxy
        vm.prank(chad);
        strategyProxy.approveFactory(address(curveFactory), true);
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

        // trade factory should sweep out CVX, and we mint the strategy _profitAmount of asset
        uint256 cvxBalance = cvx.balanceOf(address(strategy));

        // if we have CVX, sweep it out, and send back our designated profitAmount
        if (cvxBalance > 0) {
            console2.log(
                "CVX sitting in our strategy",
                cvxBalance / 1e18,
                "* 1e18 CVX"
            );
            vm.prank(tradeFactory);
            cvx.transferFrom(address(strategy), tradeFactory, cvxBalance);
            airdrop(asset, address(strategy), _profitAmount);
            cvxBalance = cvx.balanceOf(address(strategy));
        }

        // confirm that we swept everything out
        assertEq(crvBalance, 0, "!crvBalance");
        assertEq(cvxBalance, 0, "!cvxBalance");
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

    function test_setup() public {}
}

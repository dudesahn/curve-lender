// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {LlamaLendConvexFactory} from "src/LlamaLendConvexFactory.sol";
import {LlamaLendCurveFactory} from "src/LlamaLendCurveFactory.sol";
import {IProxy} from "src/interfaces/ICurveInterfaces.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// forge script script/DeployBothStrategies.s.sol:DeployBothStrategies --account llc2 --rpc-url $ETH_RPC_URL -vvvvv

// do real deployment. no need to verify since this is just a normal function call, essentially
// forge script script/DeployBothStrategies.s.sol:DeployBothStrategies --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --broadcast

contract DeployBothStrategies is Script {
    /// @notice Curve strategy factory
    LlamaLendCurveFactory public constant CURVE_FACTORY =
        LlamaLendCurveFactory(0xD35172F22df511cA5e0C8c30a8F1d75103DD0Db4);

    /// @notice Convex strategy factory
    LlamaLendConvexFactory public constant CONVEX_FACTORY =
        LlamaLendConvexFactory(0xE52B0F6615BEd0569878dCc6d35c90E1241Cd646);

    /// @notice Yearn's strategy proxy, used to check if our curve factory is endorsed
    IProxy public constant strategyProxy =
        IProxy(0x78eDcb307AC1d1F8F5Fd070B377A6e69C8dcFC34);

    // vars for each deployment
    // sDOLA v2, deployed both ✅
    //     address public curveLendVault = 0x992B77179A5cF876bcD566FF4b3EAE6482012B90;
    //     address public curveLendGauge = 0xA21043Df8d25DC876F38Bc5C7e54285F3e1a936b;
    //     uint256 public pid = 445;
    //     string public curveStrategyName = "Curve Boosted crvUSD-sDOLA Lender";
    //     string public convexStrategyName = "Convex crvUSD-sDOLA Lender";

    // sDOLA v1 (Curve only), deployed ✅
    //     address public curveLendVault = 0x14361C243174794E2207296a6AD59bb0Dec1d388;
    //     address public curveLendGauge = 0x30e06CADFbC54d61B7821dC1e58026bf3435d2Fe;
    //     uint256 public pid = 0;
    //     string public curveStrategyName = "Curve crvUSD-sDOLAv1 Lender";
    //     string public convexStrategyName = "N/A";

    // WETH v1 (Curve only)
    //     address public curveLendVault = 0x5AE28c9197a4a6570216fC7e53E7e0221D7A0FEF;
    //     address public curveLendGauge = 0x1Cfabd1937e75E40Fa06B650CB0C8CD233D65C20;
    //     uint256 public pid = 0;
    //     string public curveStrategyName = "Curve crvUSD-WETHv1 Lender";
    //     string public convexStrategyName = "N/A";

    // tBTC v1 (Curve only)
    //     address public curveLendVault = 0xb2b23C87a4B6d1b03Ba603F7C3EB9A81fDC0AAC9;
    //     address public curveLendGauge = 0x41eBf0bEC45642A675e8b7536A2cE9c078A814B4;
    //     uint256 public pid = 0;
    //     string public curveStrategyName = "Curve Boosted crvUSD-tBTCv1 Lender";
    //     string public convexStrategyName = "N/A";

    // all legacy curve lend vaults were revoked here: https://github.com/yearn/chief-multisig-officer/pull/1533/files

    // wstETH (v2 version revoked), deployed both ✅
    address public curveLendVault = 0x21CF1c5Dc48C603b89907FE6a7AE83EA5e3709aF;
    address public curveLendGauge = 0x0621982CdA4fD4041964e91AF4080583C5F099e1;
    uint256 public pid = 364;
    string public curveStrategyName = "Curve Boosted crvUSD-wstETH Lender";
    string public convexStrategyName = "Convex crvUSD-wstETH Lender";

    // USDe (v2 version revoked), deployed both ✅
    //     address public curveLendVault = 0xc687141c18F20f7Ba405e45328825579fDdD3195;
    //     address public curveLendGauge = 0xEAED59025d6Cf575238A9B4905aCa11E000BaAD0;
    //     uint256 public pid = 371;
    //     string public curveStrategyName = "Curve Boosted crvUSD-USDe Lender";
    //     string public convexStrategyName = "Convex crvUSD-USDe Lender";

    // sfrxUSD, deployed both ✅
    //     address public curveLendVault = 0x8E3009b59200668e1efda0a2F2Ac42b24baa2982;
    //     address public curveLendGauge = 0x9E7641A394859860210203e6D9cb82044712421C;
    //     uint256 public pid = 438;
    //     string public curveStrategyName = "Curve Boosted crvUSD-sfrxUSD Lender";
    //     string public convexStrategyName = "Convex crvUSD-sfrxUSD Lender";

    // sUSDe (v2 version revoked), deployed both ✅
    //     address public curveLendVault = 0x4a7999c55d3a93dAf72EA112985e57c2E3b9e95D;
    //     address public curveLendGauge = 0xAE1680Ef5EFc2486E73D8d5D0f8a8dB77DA5774E;
    //     uint256 public pid = 361;
    //     string public curveStrategyName = "Curve Boosted crvUSD-sUSDe Lender";
    //     string public convexStrategyName = "Convex crvUSD-sUSDe Lender";

    // WBTC (v2 version revoked), deployed both ✅
    //     address public curveLendVault = 0xccd37EB6374Ae5b1f0b85ac97eFf14770e0D0063;
    //     address public curveLendGauge = 0x7dCB252f7Ea2B8dA6fA59C79EdF63f793C8b63b6;
    //     uint256 public pid = 344;
    //     string public curveStrategyName = "Curve Boosted crvUSD-WBTC Lender";
    //     string public convexStrategyName = "Convex crvUSD-WBTC Lender";

    // WETH (v2 version revoked)
    //     address public curveLendVault = 0x8fb1c7AEDcbBc1222325C39dd5c1D2d23420CAe3;
    //     address public curveLendGauge = 0xF3F6D6d412a77b680ec3a5E35EbB11BbEC319739;
    //     uint256 public pid = 365;
    //     string public curveStrategyName = "Curve Boosted crvUSD-WETH Lender";
    //     string public convexStrategyName = "Convex crvUSD-WETH Lender";

    // sUSDS
    //     address public curveLendVault = 0xc33aa628b10655B36Eaa7ee880D6Bc4789dD2289;
    //     address public curveLendGauge = 0x1a915D963EE65943387dd35F54F0296BE4f925e5;
    //     uint256 public pid = 453;
    //     string public curveStrategyName = "Curve Boosted crvUSD-sUSDS Lender";
    //     string public convexStrategyName = "Convex crvUSD-sUSDS Lender";

    // CRV (maybe don't need Convex version immediately)
    //     address public curveLendVault = 0xCeA18a8752bb7e7817F9AE7565328FE415C0f2cA;
    //     address public curveLendGauge = 0x49887dF6fE905663CDB46c616BfBfBB50e85a265;
    //     uint256 public pid = 325;
    //     string public curveStrategyName = "Curve Boosted crvUSD-CRV Lender";
    //     string public convexStrategyName = "Convex crvUSD-CRV Lender";

    function run() external {
        vm.startBroadcast();
        // make sure our factory can deploy curve voter strategies AND we haven't already deployed this one
        if (
            strategyProxy.approvedFactories(address(CURVE_FACTORY)) &&
            CURVE_FACTORY.deployments(curveLendVault) == address(0)
        ) {
            address curveStrategy = CURVE_FACTORY.newCurveLender(
                curveStrategyName,
                curveLendVault,
                curveLendGauge
            );

            console2.log("-----------------------------");
            console2.log("Curve strategy deployed: ", curveStrategy);
            console2.log("-----------------------------");
        }

        // make sure we haven't already deployed this one
        // if we want to avoid deploying convex for a position (ie, for lending only), then set pid to 0
        if (
            CONVEX_FACTORY.deployments(curveLendVault) == address(0) && pid != 0
        ) {
            address convexStrategy = CONVEX_FACTORY.newConvexLender(
                convexStrategyName,
                curveLendVault,
                pid
            );

            console2.log("-----------------------------");
            console2.log("Convex strategy deployed: ", convexStrategy);
            console2.log("-----------------------------");
        }

        vm.stopBroadcast();
    }
}

// sDOLA NEW Curve: 0x279C50b6895126BBbcF9d2ED7c3FB59bdc8a18dF Convex: 0x75b7DB3e11138134fe4744553b5e5e3D6546d289
// sUSDe  Curve: 0x6AbBda8243F4BF130a97beae759A6e91522520b9 Convex: 0x6C2C45429b76406b3aAbB37b829F0B57C7badbBe
// sfrxUSD  Curve: 0xf91a9A1C782a1C11B627f6E576d92C7d72CDd4AF Convex: 0x7A26C6c1628c86788526eFB81f37a2ffac243A98
// USDe  Curve: 0x2d2C784f45D9FCCE8a5bF9ebf4ee01FA6f064D1D Convex: 0x4058dec53A72f97327dE7dD406C7E2dFD19F9a86
// WBTC  Curve: 0xEC1b4489a2DA2b0F7Fb240604f305804Da2CEB1c Convex: 0xBEE5Ce147a7F735C94DF37a50c82296861B5FEF5
// sDOLAv1  Curve: 0xab4037b34d76ba0D42F5828B2214d1BAEe395596 Convex: N/A
// wstETH  Curve: 0x2d45C2835CEA592F75E72e656932aa60d474dDF3 Convex: 0x8E6631Ff8D431a6122fDF0bfE756F624Dd3744e7
// ASSET  Curve: Convex:
// ASSET  Curve: Convex:
// ASSET  Curve: Convex:

// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {LlamaLendCurveOracle} from "src/periphery/StrategyAprOracleCurve.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// make sure to flip on optimization in foundry.toml if not using the flag in the command line
// forge script script/DeployCurveAprOracle.s.sol:DeployCurveAprOracle --account llc2 --rpc-url $ETH_RPC_URL -vvvvv

// do real deployment, try slow to see if that helps w/ verification
// forge script script/DeployCurveAprOracle.s.sol:DeployCurveAprOracle --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --etherscan-api-key $ETHERSCAN_TOKEN --slow --verify --broadcast

// verify:
// needed to manually verify, can copy-paste abi-encoded constructor args from the printed output of the deployment. this command ends with the address and contract to verify, always
// no constructor (or thus, constructor args) on this one
// forge verify-contract --rpc-url $ETH_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "0xD9192c9d5BCC72273793870a83D3eCFA4a08baaD" LlamaLendCurveOracle

contract DeployCurveAprOracle is Script {
    function run() external {
        vm.startBroadcast();

        LlamaLendCurveOracle aprOracle = new LlamaLendCurveOracle();

        console2.log("-----------------------------");
        console2.log("apr oracle deployed at: %s", address(aprOracle));
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }
}

// apr oracle V1 deployed at: 0xD9192c9d5BCC72273793870a83D3eCFA4a08baaD
// apr oracle V2 deployed at: 0xff7020A542D8fD2591615C6B8EC33e30b61f67b5 (this one returns 0 when withdrawing more than is free)
// apr oracle V3 deployed at:  (this one reverts when withdrawing more than is free)

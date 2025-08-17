// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {LlamaLendConvexOracle} from "src/periphery/StrategyAprOracleConvex.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// forge script script/DeployConvexAprOracle.s.sol:DeployConvexAprOracle --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --optimize true

// do real deployment, try slow to see if that helps w/ verification
// forge script script/DeployConvexAprOracle.s.sol:DeployConvexAprOracle --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --optimize true --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast

// verify: automatically verified successfully

contract DeployConvexAprOracle is Script {
    function run() external {
        vm.startBroadcast();

        LlamaLendConvexOracle aprOracle = new LlamaLendConvexOracle();

        console2.log("-----------------------------");
        console2.log("apr oracle deployed at: %s", address(aprOracle));
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }
}

// apr oracle deployed at: 0x795F98f75b242791e395Fc35f48C0C456C33bbAf

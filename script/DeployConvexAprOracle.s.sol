// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {LlamaLendConvexOracle} from "src/periphery/StrategyAprOracleConvex.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// make sure to flip on optimization in foundry.toml if not using the flag in the command line
// forge script script/DeployConvexAprOracle.s.sol:DeployConvexAprOracle --account llc2 --rpc-url $ETH_RPC_URL -vvvvv

// do real deployment, try slow to see if that helps w/ verification
// forge script script/DeployConvexAprOracle.s.sol:DeployConvexAprOracle --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast

// verify
// forge verify-contract --rpc-url $ETH_RPC_URL --watch --etherscan-api-key $ETHERSCAN_TOKEN "0x843851a817213BB75196C57fb60fFe1D07fC3204" LlamaLendConvexOracle

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

// apr oracle V1 deployed at: 0x795F98f75b242791e395Fc35f48C0C456C33bbAf
// apr oracle V2 deployed at: 0x843851a817213BB75196C57fb60fFe1D07fC3204 (amm.rate() fix and reverts when withdrawing more than is free)

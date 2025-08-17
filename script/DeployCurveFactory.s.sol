// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {LlamaLendCurveFactory} from "src/LlamaLendCurveFactory.sol";

import "forge-std/Script.sol";

// ---- Usage ----
// this will alert you in case your contract needs to be optimized—if so make sure to update foundry.toml
// note: once you add optimizer to foundry.toml, it seems that remappings break if you remove it. but can set to false instead and it doesn't break, lol
// forge script script/DeployCurveFactory.s.sol:DeployCurveFactory --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --optimize true

// do real deployment
// forge script script/DeployCurveFactory.s.sol:DeployCurveFactory --account llc2 --rpc-url $ETH_RPC_URL -vvvvv --optimize true --etherscan-api-key $ETHERSCAN_TOKEN --verify --broadcast

// verify:
// needed to manually verify, can copy-paste abi-encoded constructor args from the printed output of the deployment. this command ends with the address and contract to verify, always
// args: 000000000000000000000000d0002c648cca8dee2f2b8d70d542ccde8ad6ec03000000000000000000000000d0002c648cca8dee2f2b8d70d542ccde8ad6ec03000000000000000000000000d0002c648cca8dee2f2b8d70d542ccde8ad6ec0300000000000000000000000016388463d60ffe0661cf7f1f31a7d658ac790ff7
// forge verify-contract --rpc-url $ETH_RPC_URL --watch --constructor-args PASTED_HERE --etherscan-api-key $ETHERSCAN_TOKEN "" LlamaLendCurveFactory

contract DeployCurveFactory is Script {
    /// @notice Deployer
    address public constant MANAGEMENT =
        0xd0002c648CCa8DeE2f2b8D70D542Ccde8ad6EC03;

    /// @notice Deployer
    address public constant KEEPER = 0xd0002c648CCa8DeE2f2b8D70D542Ccde8ad6EC03;

    /// @notice SMS on mainnet
    address public constant EMERGENCY_ADMIN =
        0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    /// @notice Deployer
    address public constant PERFORMANCE_FEE_RECIPIENT =
        0xd0002c648CCa8DeE2f2b8D70D542Ccde8ad6EC03;

    function run() external {
        vm.startBroadcast();
        address factory = address(
            new LlamaLendCurveFactory(
                MANAGEMENT,
                PERFORMANCE_FEE_RECIPIENT,
                KEEPER,
                EMERGENCY_ADMIN
            )
        );

        console2.log("-----------------------------");
        console2.log("factory deployed at: ", factory);
        console2.log("-----------------------------");

        vm.stopBroadcast();
    }
}

// Factory V1 (3.0.2 Tokenized Strategy): 0x1979D57e4Ed5104CCD3053A3761484875a42873E
// Factory V2 (3.0.4 Tokenized Strategy): 0xD35172F22df511cA5e0C8c30a8F1d75103DD0Db4

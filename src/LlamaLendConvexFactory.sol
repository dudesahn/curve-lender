// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {StrategyLlamaLendConvex} from "./StrategyLlamaLendConvex.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

// test commit

contract LlamaLendConvexFactory {
    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public immutable emergencyAdmin;

    /// @notice Track the deployments. 4626 vault token => strategy
    mapping(address => address) public deployments;

    // crvUSD token address
    address internal constant CRVUSD =
        0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    // convex booster address
    address internal constant BOOSTER =
        0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    event NewConvexLender(address indexed strategy, address indexed vault);

    constructor(
        address _management,
        address _peformanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        management = _management;
        performanceFeeRecipient = _peformanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    /**
     * @notice Deploy a new Llama Lend Convex Strategy.
     * @dev This will set the msg.sender to all of the permissioned roles. Can only be called by management.
     * @param _name The name for the lender to use.
     * @param _vault The address of the vault token.
     * @param _pid The PID corresponding to the Convex pool.
     * @return . The address of the new lender.
     */
    function newConvexLender(
        string memory _name,
        address _vault,
        uint256 _pid
    ) external returns (address) {
        require(msg.sender == management, "!management");
        // We need to use the custom interface with the tokenized strategies available setters.
        // the only asset we will use in this factory is crvUSD
        // strategy checks that pid and vault token match, so factory doesn't need to
        IStrategyInterface newStrategy = IStrategyInterface(
            address(
                new StrategyLlamaLendConvex(
                    CRVUSD,
                    _name,
                    _vault,
                    _pid,
                    BOOSTER
                )
            )
        );
        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewConvexLender(address(newStrategy), _vault);

        deployments[_vault] = address(newStrategy);

        return address(newStrategy);
    }

    /**
     * @notice Check if a strategy has been deployed by this Factory
     * @param _strategy strategy address
     */
    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _vault = IStrategyInterface(_strategy).vault();
        return deployments[_vault] == _strategy;
    }

    /**
     * @notice Set important addresses for this factory.
     * @param _management The address to set as the management address.
     * @param _performanceFeeRecipient The address to set as the performance fee recipient address.
     * @param _keeper The address to set as the keeper address.
     */
    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        require(
            _performanceFeeRecipient != address(0) && _management != address(0),
            "ZERO_ADDRESS"
        );
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }
}

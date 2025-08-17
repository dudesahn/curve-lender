// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

import {StrategyLlamaLendConvex} from "src/StrategyLlamaLendConvex.sol";
import {IStrategyInterface} from "src/interfaces/IStrategyInterface.sol";

contract LlamaLendConvexFactory {
    /// @notice Management role controls important setters on this factory and deployed strategies
    address public management;

    /**
     * @notice Operator role is the only non-management address that can deploy new strategies
     * @dev Useful for allowing permissionless deployments via external smart contract
     */
    address public operator;

    /// @notice This address receives any performance fees
    address public performanceFeeRecipient;

    /// @notice Keeper address is allowed to report and tend deployed strategies
    address public keeper;

    /// @notice Address authorized for emergency procedures (shutdown and withdraw) on strategy
    address public emergencyAdmin;

    /// @notice Track the deployments. 4626 vault token => strategy
    mapping(address vault => address strategy) public deployments;

    // crvUSD token address
    address internal constant CRVUSD =
        0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    // convex booster address
    address internal constant BOOSTER =
        0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    event NewConvexLender(address indexed strategy, address indexed vault);
    event AddressesSet(
        address indexed management,
        address indexed emergencyAdmin,
        address indexed operator,
        address keeper,
        address performanceFeeRecipient
    );

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        require(
            _performanceFeeRecipient != address(0) &&
                _management != address(0) &&
                _emergencyAdmin != address(0),
            "ZERO_ADDRESS"
        );
        management = _management;
        emergencyAdmin = _emergencyAdmin;
        performanceFeeRecipient = _performanceFeeRecipient;
        //slither-disable-next-line missing-zero-check
        keeper = _keeper;
    }

    /**
     * @notice Deploy a new Llama Lend Convex Strategy.
     * @dev Can only be called by management or a designated operator.
     * @param _name The name for the lender to use.
     * @param _vault The address of the vault token.
     * @param _pid The PID corresponding to the Convex pool.
     * @return strategy The address of the new lender.
     */
    function newConvexLender(
        string memory _name,
        address _vault,
        uint256 _pid
    ) external returns (address strategy) {
        // slither-disable-start reentrancy-no-eth,reentrancy-events
        require(
            msg.sender == management || msg.sender == operator,
            "!authorized"
        );

        // make sure we don't already have a strategy deployed for this vault/pid
        require(deployments[_vault] == address(0), "strategy exists");

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

        strategy = address(newStrategy);
        // slither-disable-end reentrancy-no-eth,reentrancy-events
    }

    /**
     * @notice Check if a strategy has been deployed by this Factory
     * @param _strategy strategy address
     */
    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        try IStrategyInterface(_strategy).vault() returns (address _vault) {
            return deployments[_vault] == _strategy;
        } catch {
            // If the call fails or reverts, return false
            return false;
        }
    }

    /**
     * @notice Set important addresses for this factory.
     * @param _management The address to set as the management address.
     * @param _performanceFeeRecipient The address to set as the performance fee recipient address.
     * @param _keeper The address to set as the keeper address.
     * @param _emergencyAdmin The address to set as the emergencyAdmin address.
     * @param _operator A non-management address allowed to deploy new strategies.
     */
    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin,
        address _operator
    ) external {
        require(msg.sender == management, "!management");
        require(
            _performanceFeeRecipient != address(0) &&
                _management != address(0) &&
                _emergencyAdmin != address(0),
            "ZERO_ADDRESS"
        );
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        //slither-disable-next-line missing-zero-check
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        //slither-disable-next-line missing-zero-check
        operator = _operator;

        emit AddressesSet(
            _management,
            _emergencyAdmin,
            _operator,
            _keeper,
            _performanceFeeRecipient
        );
    }
}

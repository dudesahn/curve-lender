// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {StrategyLlamaLendCurve} from "./StrategyLlamaLendCurve.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

interface IVoter {
    function strategy() external view returns (address);
}

interface IProxy {
    function approveStrategy(address _gauge, address _strategy) external;

    function strategies(address) external view returns (address);
}

contract LlamaLendCurveFactory {
    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public immutable emergencyAdmin;

    /// @notice Track the deployments. 4626 vault token => strategy
    mapping(address => address) public deployments;

    // crvUSD token address
    address internal constant CRVUSD =
        0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    // yearn's veCRV voter address
    address internal constant strategyProxy =
        0x78eDcb307AC1d1F8F5Fd070B377A6e69C8dcFC34;

    event NewCurveLender(address indexed strategy, address indexed vault);

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
     * @notice Deploy a new Llama Lend Curve Strategy.
     * @dev This will set the msg.sender to all of the permissioned roles. Can only be called by management.
     * @param _name The name for the lender to use.
     * @param _vault The address of the vault token.
     * @param _gauge The address of the vault's gauge.
     * @return . The address of the new lender.
     */
    function newCurveLender(
        string memory _name,
        address _vault,
        address _gauge
    ) external returns (address) {
        require(msg.sender == management, "!management");

        // We need to use the custom interface with the tokenized strategies available setters.
        // the only asset we will use in this factory is crvUSD
        // strategy checks that gauge and vault token match, so factory doesn't need to
        require(
            IProxy(strategyProxy).strategies(_gauge) == address(0),
            "strategy exists"
        );

        IStrategyInterface newStrategy = IStrategyInterface(
            address(
                new StrategyLlamaLendCurve(
                    CRVUSD,
                    _name,
                    _vault,
                    _gauge,
                    strategyProxy
                )
            )
        );
        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewCurveLender(address(newStrategy), _vault);

        deployments[_vault] = address(newStrategy);

        // approve the new strategy/gauge combo on our strategy proxy
        IProxy(strategyProxy).approveStrategy(_gauge, address(newStrategy));

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

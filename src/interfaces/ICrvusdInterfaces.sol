// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface ICurveStrategyProxy {
    function balanceOf(address _gauge) external view returns (uint256);

    function harvest(address _gauge) external;

    function claimManyRewards(address _gauge, address[] memory _token) external;

    function deposit(address _gauge, address _token) external;

    function withdraw(
        address _gauge,
        address _token,
        uint256 _amount
    ) external returns (uint256);

    function approveStrategy(address _gauge, address _strategy) external;
}

interface IGauge {
    function lp_token() external view returns (address);
}

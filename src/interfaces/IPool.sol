// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IPool {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);

    function price_oracle(uint256 i) external view returns (uint256);
}

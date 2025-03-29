// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IFraxLend {
    function currentRateInfo()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256);

    function getPairAccounting()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256);
}

contract FraxLend4626Oracle {
    uint256 internal constant SECONDS_PER_YEAR = 31536000;

    /**
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return oracleApr The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view returns (uint256 oracleApr) {
        // pull current rate, borrows, and assets from the pair
        (, , , uint256 rate, ) = IFraxLend(_strategy).currentRateInfo();
        (uint256 assets, , uint256 borrows, , ) = IFraxLend(_strategy)
            .getPairAccounting();

        // adjust for ∆ assets
        if (_delta < 0) {
            assets = assets - uint256(-_delta);
        } else {
            assets = assets + uint256(_delta);
        }

        // spread the borrow rate across the whole supply
        oracleApr = (rate * SECONDS_PER_YEAR * borrows) / assets;
    }
}

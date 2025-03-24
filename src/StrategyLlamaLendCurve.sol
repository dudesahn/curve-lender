// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Base4626Compounder, ERC20, SafeERC20, Math} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {ICurveStrategyProxy, IGauge} from "./interfaces/ICrvusdInterfaces.sol";
import {IAuction} from "./interfaces/IAuction.sol";
import {IPool} from "./interfaces/IPool.sol";

contract StrategyLlamaLendCurve is Base4626Compounder, TradeFactorySwapper {
    using SafeERC20 for ERC20;

    struct RewardsInfo {
        /// @notice Whether we should claim CRV rewards
        bool claimCrv;
        /// @notice Whether we should claim extra rewards
        bool claimExtra;
    }

    enum SwapType {
        NULL,
        TRICRV,
        AUCTION,
        TF
    }

    /// @notice Yearns strategyProxy, needed for interacting with our Curve Voter.
    ICurveStrategyProxy public immutable proxy;

    /// @notice Info about our rewards. See struct NatSpec for more details.
    RewardsInfo public rewardsInfo;

    /// @notice Curve gauge address corresponding to our Curve Lend LP
    address public immutable gauge;

    /// @notice Address for our reward token auction
    address public auction;

    // Mapping to be set by management for any reward tokens.
    // This can be used to set different mins for different tokens
    // or to set to uin256.max if selling a reward token is reverting
    mapping(address => uint256) public minAmountToSellMapping;

    /// @notice Mapping for token address => swap type.
    /// @dev Used to set different swap methods for each reward token.
    mapping(address => SwapType) public swapType;

    /// @notice All reward tokens sold by this strategy by any method.
    address[] public allRewardTokens;

    /// @notice Minimum amount out in BPS based on oracle pricing. 9900 = 1% slippage allowed
    uint256 public minOutBps = 9900;

    /// @notice Address for TriCRV pool to sell CRV => crvUSD
    IPool internal constant TRICRV =
        IPool(0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14);

    /// @notice CRV token address
    ERC20 internal constant CRV =
        ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    /**
     * @param _asset Underlying asset to use for this strategy.
     * @param _name Name to use for this strategy. Ideally something human readable for a UI to use.
     * @param _vault ERC4626 vault token to use. In Curve Lend, these are the base LP tokens.
     * @param _gauge Gauge address for the Curve Lend LP.
     * @param _proxy Address for Yearn's strategy proxy.
     */
    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _gauge,
        address _proxy
    ) Base4626Compounder(_asset, _name, _vault) {
        require(_vault == IGauge(_gauge).lp_token(), "gauge mismatch");
        gauge = _gauge;
        proxy = ICurveStrategyProxy(_proxy);
        CRV.forceApprove(address(TRICRV), type(uint256).max);
    }

    /* ========== BASE4626 FUNCTIONS ========== */

    /// @notice Balance of 4626 vault tokens held in our strategy proxy
    /// @dev Note that Curve Lend vaults are diluted 1000:1 on deposit
    function balanceOfStake() public view override returns (uint256 stake) {
        stake = proxy.balanceOf(gauge);
    }

    function _stake() internal override {
        // send any loose 4626 vault tokens to yearn's proxy to deposit to the gauge and send to the voter
        ERC20(address(vault)).safeTransfer(address(proxy), balanceOfVault());
        proxy.deposit(gauge, address(vault));
    }

    function _unStake(uint256 _amount) internal override {
        // _amount is already in 4626 vault shares, no need to convert from asset
        proxy.withdraw(gauge, address(vault), _amount);
    }

    function vaultsMaxWithdraw() public view override returns (uint256) {
        // we use the gauge address here since that's where our strategy proxy deposits the LP
        // should be the minimum of what the gauge can redeem (limited by utilization), and our staked balance + loose vault tokens
        return
            vault.convertToAssets(
                Math.min(
                    vault.maxRedeem(gauge),
                    balanceOfStake() + balanceOfVault()
                )
            );
    }

    // allow keepers to deposit idle profit to curve lend positions as needed
    function _tend(uint256 _totalIdle) internal override {
        _deployFunds(_totalIdle);
    }

    /* ========== TRADE FACTORY & AUCTION FUNCTIONS ========== */

    function claimRewards() external override onlyManagement {
        _claimRewards();
    }

    function _claimRewards() internal override {
        RewardsInfo memory rewards = rewardsInfo;
        if (rewards.claimCrv) {
            proxy.harvest(gauge);
        }

        // claim any extra rewards we may have beyond CRV
        if (rewards.claimExtra) {
            // technically we shouldn't pass CRV here, but since we know llama lend uses
            //  newer gauges, this won't be an issue in practice
            proxy.claimManyRewards(gauge, allRewardTokens);
        }
    }

    function _claimAndSellRewards() internal override {
        // claim rewards
        _claimRewards();

        address[] memory _allRewardTokens = allRewardTokens;
        uint256 _length = _allRewardTokens.length;

        // should really re-work all of this based on CRV selling

        for (uint256 i; i < _length; ++i) {
            address token = _allRewardTokens[i];
            SwapType _swapType = swapType[token];
            uint256 balance = ERC20(token).balanceOf(address(this));

            if (balance > minAmountToSellMapping[token]) {
                if (_swapType == SwapType.TRICRV && token == address(CRV)) {
                    _swapCrvToStable(balance);
                }
            }
        }
    }

    function _swapCrvToStable(uint256 _amount) internal {
        // atomic swaps should always be sent via private mempool but use price_oracle as backstop
        uint256 crvPrice = TRICRV.price_oracle(1);
        uint256 minAmount = (_amount * crvPrice * minOutBps) / (1e18 * 10_000);
        TRICRV.exchange(2, 0, _amount, minAmount);
    }

    function kickAuction(
        address _token
    ) external onlyKeepers returns (uint256) {
        require(swapType[_token] == SwapType.AUCTION, "!auction");
        return _kickAuction(_token);
    }

    /**
     * @dev Kick an auction for a given token.
     * @param _from The token that was being sold.
     */
    function _kickAuction(address _from) internal virtual returns (uint256) {
        require(
            _from != address(asset) && _from != address(vault),
            "cannot kick"
        );
        uint256 _balance = ERC20(_from).balanceOf(address(this));
        ERC20(_from).safeTransfer(auction, _balance);
        return IAuction(auction).kick(_from);
    }

    function getAllRewardTokens() external view returns (address[] memory) {
        return allRewardTokens;
    }

    function addRewardToken(
        address _token,
        SwapType _swapType
    ) external onlyManagement {
        require(
            _token != address(asset) && _token != address(vault),
            "!allowed"
        );

        // make sure we haven't already set a swap type for this asset
        require(swapType[_token] == SwapType.NULL, "!exists");

        // shouldn't ever add an asset but set to null
        require(_swapType != SwapType.NULL, "!null");

        allRewardTokens.push(_token);
        swapType[_token] = _swapType;

        // enable on our trade factory
        if (_swapType == SwapType.TF) {
            _addToken(_token, address(asset));
        }
    }

    function removeRewardToken(address _token) external onlyManagement {
        address[] memory _allRewardTokens = allRewardTokens;
        uint256 _length = _allRewardTokens.length;
        SwapType _swapType = swapType[_token];

        for (uint256 i; i < _length; ++i) {
            if (_allRewardTokens[i] == _token) {
                allRewardTokens[i] = _allRewardTokens[_length - 1];
                allRewardTokens.pop();
            }
        }
        delete swapType[_token];
        delete minAmountToSellMapping[_token];

        // disable on our trade factory
        if (_swapType == SwapType.TF) {
            _removeToken(_token, address(asset));
        }
    }

    /* ========== PERMISSIONED SETTER FUNCTIONS ========== */

    /**
     * @notice Use to set whether we claim CRV and/or extra rewards.
     * @dev Can only be called by management.
     * @param _claimCrv Flag to claim CRV rewards.
     * @param _claimExtra Flag to claim extra gauge rewards.
     */
    function setClaimFlags(
        bool _claimCrv,
        bool _claimExtra
    ) external onlyManagement {
        rewardsInfo.claimCrv = _claimCrv;
        rewardsInfo.claimExtra = _claimExtra;
    }

    /**
     * @notice Use to update our trade factory.
     * @dev Can only be called by management.
     * @param _tradeFactory Address of new trade factory.
     */
    function setTradeFactory(address _tradeFactory) external onlyManagement {
        _setTradeFactory(_tradeFactory, address(asset));
    }

    /**
     * @notice Use to update our auction address.
     * @dev Can only be called by management.
     * @param _auction Address of new auction.
     */
    function setAuction(address _auction) external onlyManagement {
        if (_auction != address(0)) {
            require(IAuction(_auction).want() == address(asset), "wrong want");
            require(
                IAuction(_auction).receiver() == address(this),
                "wrong receiver"
            );
        }
        auction = _auction;
    }

    /**
     * @notice Set the swap type for a specific token.
     * @param _from The address of the token to set the swap type for.
     * @param _swapType The swap type to set.
     */
    function setSwapType(
        address _from,
        SwapType _swapType
    ) external onlyManagement {
        // just remove instead of setting to null
        require(_swapType != SwapType.NULL, "!null");
        swapType[_from] = _swapType;
    }

    /**
     * @notice Set our minOut BPS amount for atomic swaps.
     * @dev For example, 9990 means we allow max of 0.1% deviation in minOut from oracle pricing for swaps.
     * @param _minOutBps The amount of token we expect out in BPS based on pool oracle pricing.
     */
    function setMinOutBps(uint256 _minOutBps) external onlyManagement {
        require(_minOutBps < 10_000, "not bps");
        require(_minOutBps > 9000, "10% max");
        minOutBps = _minOutBps;
    }

    /**
     * @notice Set the `minAmountToSellMapping` for a specific `_token`.
     * @dev This can be used by management to adjust wether or not the
     * _claimAndSellRewards() function will attempt to sell a specific
     * reward token. This can be used if liquidity is to low, amounts
     * are to low or any other reason that may cause reverts.
     *
     * @param _token The address of the token to adjust.
     * @param _amount Min required amount to sell.
     */
    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external onlyManagement {
        minAmountToSellMapping[_token] = _amount;
    }
}

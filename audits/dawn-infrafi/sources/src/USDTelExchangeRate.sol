// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "solady/auth/Ownable.sol";

contract USDTelExchangeRate is Ownable {
    struct ExchangeRate {
        uint128 usdtelExchangeRate;
        uint64 timestamp;
    }

    /// @dev Number of seconds in a year, used to annualize the rate growth.
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @dev Fixed-point scale for APY values. `1e18` represents 100% APY,
    ///      so `_apyCeiling` must be supplied using the same scale.
    uint256 public constant APY_SCALE = 1e18;

    /// @dev The maximum APY allowed for the exchange rate.
    uint256 public immutable _apyCeiling;

    /// @dev The current exchange rate.
    ExchangeRate public _exchangeRate;

    /// @dev The address authorized to post exchange rate updates. This is kept
    ///      separate from {owner}: the owner is a cold/admin key that manages
    ///      this role, while the updater is a hot key operated by the rate feed
    ///      service. A compromised updater can only push rates (bounded by the
    ///      APY ceiling); it cannot manage ownership or the updater itself.
    address public _updater;

    error InvalidAPYCeiling(uint256 apyCeiling);
    error InvalidInitialExchangeRate(uint128 initialExchangeRate);
    error InvalidUpdater();
    error ExchangeRateDecreased();
    error StaleTimestamp();
    error ApyCeilingExceeded(uint256 apy, uint256 apyCeiling);
    error UnauthorizedUpdater();
    error RenounceDisabled();
    error TransferOwnershipDisabled();

    event ExchangeRateUpdated(uint128 newUSDTelExchangeRate, uint64 timestamp);
    event UpdaterChanged(address indexed previousUpdater, address indexed newUpdater);

    /// @dev Restricts a function to the current {_updater}.
    modifier onlyUpdater() {
        if (msg.sender != _updater) {
            revert UnauthorizedUpdater();
        }
        _;
    }

    constructor(uint256 apyCeiling, uint128 initialExchangeRate, address initialUpdater) {
        if (apyCeiling == 0) {
            revert InvalidAPYCeiling(apyCeiling);
        }
        if (initialExchangeRate == 0) {
            revert InvalidInitialExchangeRate(initialExchangeRate);
        }
        if (initialUpdater == address(0)) {
            revert InvalidUpdater();
        }

        _initializeOwner(msg.sender);
        _apyCeiling = apyCeiling;
        _exchangeRate = ExchangeRate(initialExchangeRate, uint64(block.timestamp));
        _updater = initialUpdater;
        emit UpdaterChanged(address(0), initialUpdater);
    }

    /// @notice Sets the address authorized to post exchange rate updates.
    /// @dev Only callable by the owner. The updater cannot be the zero address;
    ///      to rotate keys, point this at the new updater.
    function setUpdater(address newUpdater) public onlyOwner {
        if (newUpdater == address(0)) {
            revert InvalidUpdater();
        }
        emit UpdaterChanged(_updater, newUpdater);
        _updater = newUpdater;
    }

    function setExchangeRate(uint128 newUSDTelExchangeRate) public onlyUpdater {
        ExchangeRate memory previous = _exchangeRate;

        // The exchange rate is expected to be monotonically non-decreasing.
        if (newUSDTelExchangeRate < previous.usdtelExchangeRate) {
            revert ExchangeRateDecreased();
        }

        uint256 elapsed = block.timestamp - previous.timestamp;

        // Only validate growth; a flat (unchanged) rate is always allowed even
        // within the same block, but any increase requires elapsed time.
        if (newUSDTelExchangeRate > previous.usdtelExchangeRate) {
            if (elapsed == 0) {
                revert StaleTimestamp();
            }

            uint256 growth = newUSDTelExchangeRate - previous.usdtelExchangeRate;

            // Annualized (simple) APY for the period since the last update:
            //   apy = (growth / previousRate) * (SECONDS_PER_YEAR / elapsed)
            // scaled by APY_SCALE and computed without intermediate rounding.
            uint256 apy = (growth * SECONDS_PER_YEAR * APY_SCALE) / (uint256(previous.usdtelExchangeRate) * elapsed);

            if (apy > _apyCeiling) {
                revert ApyCeilingExceeded(apy, _apyCeiling);
            }
        }

        _exchangeRate = ExchangeRate(newUSDTelExchangeRate, uint64(block.timestamp));

        emit ExchangeRateUpdated(newUSDTelExchangeRate, uint64(block.timestamp));
    }

    function getExchangeRate() public view returns (ExchangeRate memory) {
        return _exchangeRate;
    }

    /// @dev Disabled to prevent the feed from being permanently frozen, which
    ///      would leave it unupdatable with no recovery path. Ownership can
    ///      still be transferred via {transferOwnership}.
    function renounceOwnership() public payable override onlyOwner {
        revert RenounceDisabled();
    }

    /// @dev ownnership transfer can be done only via
    ///      {requestOwnershipHandover} and {completeOwnershipHandover} functions.
    function transferOwnership(address newOwner) public payable override onlyOwner {
        revert TransferOwnershipDisabled();
    }
}

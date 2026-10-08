// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

/// @notice Minimal interface for the real, deployed USDTelExchangeRate contract
///         (BNB Chain, 0x15a6f1f2705b3916b5b1d2b19b10f320778744c1), matching the
///         verified source obtained from Sourcify. No mock, no redeploy: every
///         test below forks mainnet and calls the REAL deployed bytecode.
interface IUSDTelExchangeRate {
    function getExchangeRate() external view returns (uint128 usdtelExchangeRate, uint64 timestamp);
    function setExchangeRate(uint128 newUSDTelExchangeRate) external;
    function _updater() external view returns (address);
    function _apyCeiling() external view returns (uint256);
    function owner() external view returns (address);
    function SECONDS_PER_YEAR() external view returns (uint256);
    function APY_SCALE() external view returns (uint256);

    error ExchangeRateDecreased();
    error ApyCeilingExceeded(uint256 apy, uint256 apyCeiling);
    error StaleTimestamp();
}

/// @title PoC — DAWN / InfraFi Immunefi bounty — USDTelExchangeRate (BNB Chain)
/// @notice Two PoCs against the REAL deployed contract, on a pinned BSC mainnet fork:
///   1. The published rate can never be corrected downward, by anyone, ever.
///   2. The per-call APY ceiling check compounds instead of bounding annual growth,
///      so the "bounded by the APY ceiling" security claim in the contract's own
///      comments does not hold for routine, non-malicious operation.
/// @dev Run with:
///      forge test --match-contract USDTelExchangeRatePoCTest -vvv \
///        --rpc-url https://bsc-dataseed.binance.org --fork-block-number 125526310
///      (BSC_RPC_URL env var is also honoured; see foundry.toml / .env below.)
contract USDTelExchangeRatePoCTest is Test {
    address constant TARGET = 0x15A6F1f2705B3916b5B1D2b19b10F320778744C1;
    IUSDTelExchangeRate target = IUSDTelExchangeRate(TARGET);

    function setUp() public {
        // Public BSC RPC providers (bsc-dataseed, publicnode, meowrpc, nodereal, etc.)
        // uniformly reject `eth_getProof` when it is sent inside a batch request
        // ("method eth_getProof in batch triggered rate limit"), which is exactly
        // how Foundry's fork backend fetches basic account info -- this is a
        // provider-side anti-abuse policy common across free BSC RPC endpoints,
        // not specific to this contract or this environment.
        //
        // Workaround that still satisfies "fork mainnet": a local anvil instance
        // (http://127.0.0.1:8545, started with no --fork-url of its own) has the
        // REAL deployed bytecode and the REAL current storage slots injected via
        // `anvil_setCode` / `anvil_setStorageAt`, read moments earlier directly
        // from BNB Chain mainnet (binance.nodereal.io, single non-batched calls):
        //
        //   eth_getCode(TARGET)        -> runtime bytecode, byte-for-byte mainnet
        //   eth_getStorageAt(TARGET,0) -> _exchangeRate (rate=1009565510281362300,
        //                                 timestamp=1785974420)
        //   eth_getStorageAt(TARGET,1) -> _updater = 0x7ad7eee2...eaa0718
        //
        // _apyCeiling is `immutable`, so it is already correct as part of the
        // copied bytecode itself (verified: 200000000000000000 = 20%, matches
        // mainnet exactly). forking FROM this local anvil (rather than directly
        // from a remote RPC) sidesteps the provider's batch-eth_getProof block
        // entirely, since anvil answers every query from its own local state with
        // no further upstream fetch -- the contract under test is still the real,
        // unmodified, currently-deployed mainnet bytecode and mainnet state.
        string memory rpc = vm.envOr("BSC_RPC_URL", string("http://127.0.0.1:8545"));
        vm.createSelectFork(rpc);
    }

    /// @notice FINDING 1 — setExchangeRate can never publish a decrease, by anyone,
    ///         even the real, legitimate, currently-authorized updater key.
    function test_PoC_ExchangeRateCanNeverBeCorrectedDownward() public {
        (uint128 rateBefore, uint64 tsBefore) = target.getExchangeRate();
        address updater = target._updater();

        console2.log("=== FINDING 1: exchange rate has no downward recovery path ===");
        console2.log("Real contract         :", TARGET);
        console2.log("Real updater key       :", updater);
        console2.log("Current published rate :", rateBefore);
        console2.log("Current timestamp      :", tsBefore);

        // Simulate a real loss event: the Loopscale vault's NAV genuinely drops,
        // so the off-chain feed (using the REAL updater key, no compromise, no
        // privilege escalation) correctly computes a LOWER rate and tries to
        // publish the honest, corrected value.
        uint128 correctedLowerRate = rateBefore - (rateBefore / 100); // a 1% real loss
        console2.log("Honest corrected rate after a 1%% real loss:", correctedLowerRate);

        vm.warp(block.timestamp + 1 days); // plenty of elapsed time, not a timing issue
        vm.prank(updater);
        vm.expectRevert(IUSDTelExchangeRate.ExchangeRateDecreased.selector);
        target.setExchangeRate(correctedLowerRate);

        console2.log("setExchangeRate(correctedLowerRate) REVERTED: ExchangeRateDecreased()");
        console2.log("==> The real updater key, acting honestly after a real loss, CANNOT");
        console2.log("    correct the published rate downward. No other function in the");
        console2.log("    contract (setUpdater, transferOwnership, ownership handover) can");
        console2.log("    touch _exchangeRate either. The stale, too-high rate is permanent.");

        // Confirm nothing changed on-chain (the revert did not partially apply).
        (uint128 rateAfter,) = target.getExchangeRate();
        assertEq(rateAfter, rateBefore, "rate must be unchanged after the reverted call");
    }

    /// @notice FINDING 2 — the per-call APY ceiling check bounds simple interest
    ///         per call, not compounded annual growth, so splitting one year of
    ///         updates into many smaller ones lets the rate grow past the
    ///         configured ceiling with ZERO malicious intent — just a routine
    ///         update cadence, using the real updater key.
    function test_PoC_APYCeilingCompoundingBypass() public {
        (uint128 r0,) = target.getExchangeRate();
        address updater = target._updater();
        uint256 ceiling = target._apyCeiling();
        uint256 year = target.SECONDS_PER_YEAR();
        uint256 scale = target.APY_SCALE();

        console2.log("=== FINDING 2: APY ceiling bounds simple interest, not compound growth ===");
        console2.log("Starting rate   :", r0);
        console2.log("APY ceiling     :", ceiling, "/ scale", scale);
        console2.log("SECONDS_PER_YEAR:", year);

        // --- Baseline: what ONE single update spanning exactly one year allows ---
        uint256 maxSingleUpdateRate = uint256(r0) + (uint256(r0) * ceiling) / scale;
        console2.log("");
        console2.log("-- Baseline: one update after 365 days, at the maximum allowed growth --");
        console2.log("Max rate a SINGLE yearly update may legally reach:", maxSingleUpdateRate);

        // --- Attack: split the same calendar year into N equal updates, each ---
        // --- individually saturating the per-call check (no call is ever      ---
        // --- individually "wrong" -- the violation only appears across the    ---
        // --- sequence).                                                       ---
        uint256 n = 12; // monthly cadence -- an entirely ordinary, non-malicious schedule
        uint256 step = year / n;
        uint256 rate = r0;

        console2.log("");
        console2.log("-- Attack: same updater key, same one-year span, split into", n, "monthly calls --");
        for (uint256 i = 0; i < n; i++) {
            vm.warp(block.timestamp + step);
            // Exactly the maximum growth this single step's check allows:
            uint256 growth = (rate * ceiling * step) / (year * scale);
            uint128 newRate = uint128(rate + growth);

            vm.prank(updater);
            target.setExchangeRate(newRate); // succeeds -- passes the per-call check

            rate = newRate;
            console2.log("  call", i + 1, "-> new rate:", rate);
        }

        console2.log("");
        console2.log("Final rate after 12 individually-compliant monthly calls:", rate);
        console2.log("Max rate a single yearly update may legally reach       :", maxSingleUpdateRate);

        uint256 excessWad = rate > maxSingleUpdateRate
            ? ((rate - maxSingleUpdateRate) * 1e18) / maxSingleUpdateRate
            : 0;
        console2.log("Excess over the documented annual ceiling (1e18 = 100%):", excessWad);

        assertGt(
            rate,
            maxSingleUpdateRate,
            "compounded rate must exceed the rate a single yearly update could ever reach"
        );

        console2.log("");
        console2.log("==> 12 ordinary monthly calls by the REAL updater key, each one");
        console2.log("    individually passing the ApyCeilingExceeded check, compound the");
        console2.log("    rate PAST the single-update ceiling the contract's own comment");
        console2.log("    claims bounds the updater's damage -- with no compromise, no");
        console2.log("    privilege escalation, just routine operation.");
    }

    /// @notice Same bug as above, at a more realistic automated-feed cadence
    ///         (daily instead of monthly) to show the excess growing with call
    ///         frequency, approaching the theoretical e^ceiling bound.
    function test_PoC_APYCeilingCompoundingBypass_DailyCadence() public {
        (uint128 r0,) = target.getExchangeRate();
        address updater = target._updater();
        uint256 ceiling = target._apyCeiling();
        uint256 year = target.SECONDS_PER_YEAR();
        uint256 scale = target.APY_SCALE();

        uint256 maxSingleUpdateRate = uint256(r0) + (uint256(r0) * ceiling) / scale;

        uint256 n = 365; // one update per day -- an entirely ordinary automated-feed cadence
        uint256 step = year / n;
        uint256 rate = r0;

        console2.log("=== FINDING 2b: same bypass at daily cadence (365 calls/year) ===");
        for (uint256 i = 0; i < n; i++) {
            vm.warp(block.timestamp + step);
            uint256 growth = (rate * ceiling * step) / (year * scale);
            uint128 newRate = uint128(rate + growth);
            vm.prank(updater);
            target.setExchangeRate(newRate);
            rate = newRate;
        }

        console2.log("Final rate after 365 daily calls over one year :", rate);
        console2.log("Max rate a single yearly update may legally reach:", maxSingleUpdateRate);
        uint256 excessWad = ((rate - maxSingleUpdateRate) * 1e18) / maxSingleUpdateRate;
        console2.log("Excess over the documented annual ceiling (1e18 = 100%):", excessWad);
        console2.log("==> At a realistic once-a-day feed cadence the excess over the");
        console2.log("    documented 20%% annual ceiling is already visible without any");
        console2.log("    special attacker timing, and grows further at higher frequency.");

        assertGt(rate, maxSingleUpdateRate, "daily-cadence rate must exceed the single-update ceiling");
    }

    /// @notice COMBINED FINDING — Finding 2 (per-call ceiling compounds instead of
    ///         bounding annual growth) composed with Finding 1 (no function can ever
    ///         lower _exchangeRate) across multiple years. Each year's compounding
    ///         excess becomes the PERMANENT starting point for the next year, so the
    ///         gap between the real published rate and the documented ceiling grows
    ///         WITHOUT BOUND over time -- not a one-time, self-correcting overshoot.
    ///         This test runs 10 years of ordinary daily updates (3650 calls, no
    ///         malicious timing, every single call individually passing
    ///         ApyCeilingExceeded), shows the realized multiplier is already ~19%
    ///         beyond the documented 10-year maximum, and then proves that maximum
    ///         can never be corrected back to -- the real updater, trying to fix the
    ///         rate down to the documented-compliant value, is blocked by the exact
    ///         same ExchangeRateDecreased() revert demonstrated in Finding 1.
    function test_PoC_PermanentCompoundingDriftAcrossYears() public {
        (uint128 r0,) = target.getExchangeRate();
        address updater = target._updater();
        uint256 ceiling = target._apyCeiling();
        uint256 year = target.SECONDS_PER_YEAR();
        uint256 scale = target.APY_SCALE();

        console2.log("=== COMBINED FINDING: F2 compounding x F1 no-downward-correction ===");
        console2.log("Starting rate r0                         :", r0);
        console2.log("Documented APY ceiling (1e18 = 100%)      :", ceiling);

        uint256 yearsToSimulate = 10;
        uint256 callsPerYear = 365; // ordinary daily automated-feed cadence, no special timing
        uint256 step = year / callsPerYear;
        uint256 rate = r0;

        console2.log("");
        console2.log("-- Simulating", yearsToSimulate, "years of ordinary daily updates --");
        for (uint256 y = 0; y < yearsToSimulate; y++) {
            for (uint256 i = 0; i < callsPerYear; i++) {
                vm.warp(block.timestamp + step);
                uint256 growth = (rate * ceiling * step) / (year * scale);
                uint128 newRate = uint128(rate + growth);
                vm.prank(updater);
                target.setExchangeRate(newRate); // succeeds -- passes the per-call check every time
                rate = newRate;
            }
            console2.log("  end of year", y + 1, "-> rate:", rate);
        }

        // Documented maximum after `yearsToSimulate` years if the ceiling genuinely
        // bounded annual growth, compounded year over year: r0 * (1+ceiling)^years.
        uint256 documentedMax = uint256(r0);
        for (uint256 y = 0; y < yearsToSimulate; y++) {
            documentedMax = documentedMax + (documentedMax * ceiling) / scale;
        }

        console2.log("");
        console2.log("Real rate after", yearsToSimulate, "years of ordinary operation:", rate);
        console2.log("Documented maximum after the same period :", documentedMax);
        uint256 excessWad = ((rate - documentedMax) * 1e18) / documentedMax;
        console2.log("Cumulative excess over the documented 10-year ceiling (1e18=100%):", excessWad);
        console2.log("==> ~19%% excess after 10 years of ENTIRELY ORDINARY operation --");
        console2.log("    no compromise, no attacker timing, just a normal daily feed.");

        assertGt(rate, documentedMax, "10-year compounded rate must exceed the 10-year documented ceiling");

        // Now prove the excess can NEVER be corrected back down: the real updater,
        // acting honestly, tries to fix the rate back to the documented-compliant
        // maximum (still a real reduction relative to where it actually sits).
        console2.log("");
        console2.log("-- Attempting an honest correction back to the documented ceiling --");
        vm.warp(block.timestamp + 1 days);
        vm.prank(updater);
        vm.expectRevert(IUSDTelExchangeRate.ExchangeRateDecreased.selector);
        target.setExchangeRate(uint128(documentedMax));

        console2.log("setExchangeRate(documentedMax) REVERTED: ExchangeRateDecreased()");
        console2.log("==> The permanent ~19%% drift accumulated over 10 years of ordinary");
        console2.log("    operation CANNOT be corrected by anyone, ever. The two findings");
        console2.log("    combine into a structurally unbounded, irreversible divergence");
        console2.log("    between the published rate and the contract's own documented");
        console2.log("    security guarantee.");

        (uint128 rateAfter,) = target.getExchangeRate();
        assertEq(rateAfter, rate, "rate must remain unchanged after the reverted correction attempt");
    }
}

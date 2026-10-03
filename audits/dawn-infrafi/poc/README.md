# PoC — DAWN / InfraFi Immunefi bounty — `USDTelExchangeRate` (BNB Chain)

Runnable Foundry PoC for two findings against the real, currently-deployed contract
`0x15A6F1f2705B3916b5B1D2b19b10F320778744C1` on BNB Chain — no mock, no redeploy,
the test interacts with the actual verified bytecode (fetched from
[Sourcify](https://sourcify.dev), source also in `../sources/src/USDTelExchangeRate.sol`).

## Findings demonstrated

1. **`test_PoC_ExchangeRateCanNeverBeCorrectedDownward`** — the real, currently-authorized
   updater key cannot publish a decrease, even an honest one after a real loss.
   `setExchangeRate` reverts with `ExchangeRateDecreased()` unconditionally.
2. **`test_PoC_APYCeilingCompoundingBypass`** / **`..._DailyCadence`** — the per-call APY
   ceiling check bounds simple interest, not compounded growth, so routine, non-malicious
   update cadences (monthly or daily) push the realized annual growth past the documented
   `_apyCeiling` (currently 20%).

## Dependencies

- [Foundry](https://getfoundry.sh) (`forge`, `cast`, `anvil`) — tested with `forge 1.5.1-stable`.
- `forge-std` (installed under `lib/forge-std` via `forge init`, already vendored in this
  directory — no extra step needed if you clone this repo as-is).
- No API keys, no `.env` file, no secrets of any kind.

## Why a local `anvil` instead of `vm.createSelectFork(<public RPC>)` directly

Every free public BSC RPC endpoint tested (`bsc-dataseed.binance.org`,
`bsc-rpc.publicnode.com`, `bsc.meowrpc.com`, `binance.nodereal.io`,
`bsc-dataseed1.defibit.io`) rejects `eth_getProof` when it arrives inside a batched
JSON-RPC request:

```
{"jsonrpc":"2.0","id":null,"error":{"code":-32005,"message":"method eth_getProof in batch triggered rate limit"}}
```

Foundry's fork backend always batches this call (it is how it fetches an account's
balance/nonce/code in one round trip), so `vm.createSelectFork` against any of these
endpoints fails during `setUp()` with `missing trie node` — a provider-side anti-abuse
policy, not a bug in the target contract or an archive-node limitation.

**If you have a premium RPC endpoint** (Alchemy, Infura, QuickNode, a paid Ankr/NodeReal
key, your own node, etc.) that does not impose this restriction, you can skip the anvil
step entirely:

```bash
BSC_RPC_URL="https://your-provider/your-key" forge test --match-contract USDTelExchangeRatePoCTest -vvv
```

**Otherwise**, reproduce the real on-chain state in a local `anvil` first (takes seconds,
no archive node needed — only three single, non-batched RPC calls against any public
endpoint):

```bash
# 1. Start a plain local anvil (no --fork-url: avoids the batching issue entirely)
anvil --port 8545 --host 127.0.0.1 --chain-id 56 &

# 2. Copy the real, currently-deployed bytecode and storage into it
TO=0x15a6f1f2705b3916b5b1d2b19b10f320778744c1
RPC=https://binance.nodereal.io   # any public BSC RPC works for single calls

CODE=$(cast rpc eth_getCode "$TO" latest --rpc-url "$RPC" | tr -d '"')
SLOT0=$(cast rpc eth_getStorageAt "$TO" 0x0 latest --rpc-url "$RPC" | tr -d '"')
SLOT1=$(cast rpc eth_getStorageAt "$TO" 0x1 latest --rpc-url "$RPC" | tr -d '"')

cast rpc anvil_setCode "$TO" "$CODE" --rpc-url http://127.0.0.1:8545
cast rpc anvil_setStorageAt "$TO" 0x0 "$SLOT0" --rpc-url http://127.0.0.1:8545
cast rpc anvil_setStorageAt "$TO" 0x1 "$SLOT1" --rpc-url http://127.0.0.1:8545

# _apyCeiling is `immutable` -- it is already correct as part of the copied
# bytecode itself, no separate storage write needed. Verify the injected state
# matches mainnet exactly:
cast call "$TO" "getExchangeRate()(uint128,uint64)" --rpc-url http://127.0.0.1:8545
cast call "$TO" "_updater()(address)"               --rpc-url http://127.0.0.1:8545
cast call "$TO" "_apyCeiling()(uint256)"             --rpc-url http://127.0.0.1:8545

# 3. Run the PoC against it
forge test --match-contract USDTelExchangeRatePoCTest -vvv --rpc-url http://127.0.0.1:8545
```

The contract under test is still the real, unmodified, currently-deployed mainnet
bytecode and mainnet state — `anvil_setCode`/`anvil_setStorageAt` reconstruct it
byte-for-byte and slot-for-slot, verified by the `cast call` outputs above matching the
live values on BNB Chain exactly (`getExchangeRate() == (1009565510281362300,
1785974420)`, `_updater() == 0x7aD7EEe24ACE80bb84D1bd8fe5798b852Eaa0718`,
`_apyCeiling() == 200000000000000000`, all confirmed against mainnet on 2026-10-03).
The local anvil only replaces the *transport* Foundry's fork uses, not the state it reads.

## Expected output

See `run-output.txt` in this directory for a full run captured on 2026-10-03. Summary:

```
Ran 3 tests for test/USDTelExchangeRate.PoC.t.sol:USDTelExchangeRatePoCTest
[PASS] test_PoC_APYCeilingCompoundingBypass() (gas: 156620)
[PASS] test_PoC_APYCeilingCompoundingBypass_DailyCadence() (gas: 2899071)
[PASS] test_PoC_ExchangeRateCanNeverBeCorrectedDownward() (gas: 32837)
Suite result: ok. 3 passed; 0 failed; 0 skipped
```

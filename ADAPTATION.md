# Part 3 launch adaptation

No production contract changes were necessary. `FrenArtChunk5`, `FrenArtChunk6`
and `FrenArtChunk7` already have nonpayable, zero-argument constructors.
`FrenRenderer` already has a nonpayable constructor taking seven addresses,
checks every dependency's code hash, and stores the addresses as immutables.
It has no owner, initialization step, upgrade mechanism or mutable configuration.
The generated chunks, `FrenArtIndex`, renderer behavior, build configuration and
vendored dependencies are unchanged. The existing configuration already uses
`bytecode_hash = "none"`.

## Changes and their reasons

- `test/Part3Launch.t.sol`: adds an offline, zero-value CREATE2 factory rehearsal
  for the exact four-contract launch. The existing tests deploy with CREATE and
  scan only the chunks; this test also checks the renderer against the protected
  runtime size and forbidden-opcode rules, bounds each constructor payload,
  verifies predicted deployment addresses and all seven immutable arguments,
  and compares the resulting bitmaps with every stored reference. It estimates
  transaction gas including calldata, reserving 5% of the stated transaction cap
  for factory overhead. The probe is only a test helper, not a launch contract.
- `ADAPTATION.md`: records the compatibility decision, deployment handoff and
  validation required by this assignment.

## Deployment handoff

Deploy only these four contracts, in order:

1. `src/FrenArtChunks.sol:FrenArtChunk5`, no constructor arguments.
2. `src/FrenArtChunks.sol:FrenArtChunk6`, no constructor arguments.
3. `src/FrenArtChunks.sol:FrenArtChunk7`, no constructor arguments.
4. `src/FrenRenderer.sol:FrenRenderer`, with these seven address arguments in order:

   | Position | Argument |
   | --- | --- |
   | 1 | `0xa92dAcfF6d6fcC218ADe20eD24857376BD8eBE81` (chunk 1, launch #819) |
   | 2 | `0x9666A481e20F1dB59EEbD6c43D11Ae3505468c92` (chunk 2, launch #819) |
   | 3 | `0x71BdEB749b3ee428730eBB3E9b34B03A99D82356` (chunk 3, launch #838) |
   | 4 | `0x0C344484D960B8474a1EdcB5A5128e8D9C9F6B4d` (chunk 4, launch #838) |
   | 5 | `$contract:FrenArtChunk5` |
   | 6 | `$contract:FrenArtChunk6` |
   | 7 | `$contract:FrenArtChunk7` |

There is no launch token or owner argument. Chunk 7 retains its STOP byte and
PUSH32 framing; the renderer retains the matching code hashes and decoder.
No manifest or broadcast is part of this adaptation.

## Audit and verification

The imported audit reported **no findings**, so there were no reported findings
to reproduce, fix or dismiss. Review of the constructor and rendering paths did
not require a production behavior change. Verification uses Foundry; Slither,
Mythril and long fuzz campaigns were not run.

Checked with the project's unchanged default configuration, Foundry 1.8.3 and
Solidity 0.8.26:

- `forge build`: passed (existing renderer lint warnings remain).
- `forge test -vv`: 10 passed, 0 failed, 1 skipped. This includes the existing
  metadata/reference comparisons and rejection tests, plus the three new part-3
  factory tests.
- Part-3 CREATE2 deployment estimate including calldata: **15,293,183 gas**,
  below the test's 95% threshold of the 16,777,216 gas transaction cap. This is
  a local probe estimate, not a simulation of the production factory.
- All four deployed runtimes passed the protected floor's PUSH-aware opcode
  scan and 24,576-byte limit; all four constructor payloads fit 49,152 bytes.

The new offline test installs repository-generated chunk 1–4 bytecode at the
specified addresses. This checks address wiring, not live mainnet state.
`test/OnChainChunks.fork.t.sol` remains the live-dependency check and skips when
`MAINNET_RPC_URL` is absent, as in this run. Actual factory transaction simulation
and live dependency verification remain deployment-time checks.

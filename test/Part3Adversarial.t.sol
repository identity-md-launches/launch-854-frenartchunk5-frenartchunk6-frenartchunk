// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FrenRenderer} from "src/FrenRenderer.sol";
import {Part3Fixture} from "./helpers/Part3Fixture.sol";

contract Part3AdversarialTest is Part3Fixture {
    function _expectBadArt(address[7] memory c) internal {
        vm.expectRevert(FrenRenderer.BadArt.selector);
        _deployRenderer(c);
    }

    function test_EveryConstructorSlotRejectsZeroEmptyAccountAndWrongCode() public {
        address empty = address(0xE0A);
        vm.deal(empty, 1); // An existing account with empty code, distinct from a nonexistent account.
        address[3] memory bad = [address(0), empty, address(renderer)];
        for (uint256 slot; slot < 7; ++slot) {
            for (uint256 kind; kind < bad.length; ++kind) {
                address[7] memory c = chunks;
                c[slot] = bad[kind];
                _expectBadArt(c);
            }
        }
    }

    function test_EveryPairOfSwappedChunksIsRejected() public {
        for (uint256 i; i < 7; ++i) {
            for (uint256 j = i + 1; j < 7; ++j) {
                address[7] memory c = chunks;
                (c[i], c[j]) = (c[j], c[i]);
                _expectBadArt(c);
            }
        }
    }

    function test_EverySlotRejectsADuplicateChunk() public {
        for (uint256 i; i < 7; ++i) {
            address[7] memory c = chunks;
            c[i] = c[(i + 1) % 7];
            _expectBadArt(c);
        }
    }

    function test_EveryChunkRejectsTruncationAndAppendedData() public {
        for (uint256 i; i < 7; ++i) {
            bytes memory original = chunks[i].code;
            bytes memory shortened = new bytes(original.length - 1);
            for (uint256 j; j < shortened.length; ++j) {
                shortened[j] = original[j];
            }
            vm.etch(chunks[i], shortened);
            _expectBadArt(chunks);
            vm.etch(chunks[i], bytes.concat(original, hex"00"));
            _expectBadArt(chunks);
            vm.etch(chunks[i], original);
        }
    }

    function test_EveryChunkRejectsChangedStopMiddleAndLastByte() public {
        for (uint256 i; i < 7; ++i) {
            uint256 size = chunks[i].code.length;
            _rejectMutation(i, 0, 1);
            _rejectMutation(i, size / 2, 1);
            _rejectMutation(i, size - 1, 1);
        }
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_AnySingleByteCorruptionIsRejected(uint8 slot, uint256 offset, uint8 delta) public {
        uint256 i = bound(slot, 0, 6);
        _rejectMutation(i, bound(offset, 0, chunks[i].code.length - 1), uint8(bound(delta, 1, 255)));
    }

    function _rejectMutation(uint256 slot, uint256 offset, uint8 delta) internal {
        bytes memory original = chunks[slot].code;
        bytes memory changed = bytes.concat(original);
        changed[offset] ^= bytes1(delta);
        vm.etch(chunks[slot], changed);
        _expectBadArt(chunks);
        vm.etch(chunks[slot], original);
    }

    function test_IdenticalRuntimeAtAnotherAddressIsAccepted() public {
        address[7] memory c;
        for (uint256 i; i < 7; ++i) {
            c[i] = address(uint160(0xC000 + i));
            vm.etch(c[i], chunks[i].code);
        }
        FrenRenderer copy = _deployRenderer(c);
        assertEq(copy.chunk1(), c[0]);
        assertEq(copy.chunk7(), c[6]);
        assertEq(copy.bmp(0, type(uint256).max), renderer.bmp(0, type(uint256).max));
    }

    function test_Part3ConstructorsRejectOneWei() public {
        vm.deal(address(this), 1);
        for (uint256 i = 5; i <= 8; ++i) {
            bytes memory code = i == 8
                ? bytes.concat(vm.getCode("FrenRenderer.sol:FrenRenderer"), abi.encode(chunks))
                : vm.getCode(string.concat("FrenArtChunks.sol:FrenArtChunk", vm.toString(i)));
            address deployed;
            assembly ("memory-safe") {
                deployed := create(1, add(code, 32), mload(code))
            }
            assertEq(deployed, address(0), "constructor accepted ETH");
            assertEq(address(this).balance, 1, "failed creation lost value");
        }
    }

    function _expectMissing(uint24 combo, uint256 seed, uint256 tokenId) internal {
        vm.expectRevert(FrenRenderer.Missing.selector);
        renderer.canvas(combo, seed);
        vm.expectRevert(FrenRenderer.Missing.selector);
        renderer.bmp(combo, seed);
        vm.expectRevert(FrenRenderer.Missing.selector);
        renderer.tokenURI(tokenId, combo, seed);
    }

    function test_AllInvalidTraitEncodingsUseMissingAcrossRenderingEntrypoints() public {
        uint256[6] memory shifts = [uint256(0), 2, 8, 10, 13, 15];
        uint256[6] memory first = [uint256(3), 13, 3, 6, 3, 10];
        uint256[6] memory last = [uint256(3), 15, 3, 7, 3, 15];
        for (uint256 i; i < 6; ++i) {
            for (uint256 invalid = first[i]; invalid <= last[i]; ++invalid) {
                _expectMissing(uint24(invalid << shifts[i]), type(uint256).max, type(uint256).max);
            }
        }
        _expectMissing(type(uint24).max, 0, 0);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzz_InvalidTraitInOtherwiseValidComboReverts(
        uint256 entropy,
        uint8 field,
        uint8 invalid,
        uint256 seed,
        uint256 tokenId
    ) public {
        uint256[6] memory shifts = [uint256(0), 2, 8, 10, 13, 15];
        uint256[6] memory first = [uint256(3), 13, 3, 6, 3, 10];
        uint256[6] memory masks = [uint256(3), 15, 3, 7, 3, 15];
        uint256 f = bound(field, 0, 5);
        uint24 combo = uint24(
            (uint256(_validCombo(entropy)) & ~(masks[f] << shifts[f]))
                | (bound(invalid, first[f], masks[f]) << shifts[f])
        );
        _expectMissing(combo, seed, tokenId);
    }

    function test_RendererHasNoConfigurationOrFallbackEntrypoints() public {
        bytes[5] memory calls = [
            bytes(""),
            abi.encodeWithSignature("initialize(address)", address(this)),
            abi.encodeWithSignature("transferOwnership(address)", address(this)),
            abi.encodeWithSignature("setChunk(uint256,address)", 6, address(this)),
            abi.encodeWithSignature("withdraw()")
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok, bytes memory result) = address(renderer).call(calls[i]);
            assertFalse(ok, "unexpected configuration/fallback entrypoint");
            assertEq(result.length, 0);
        }
    }
}

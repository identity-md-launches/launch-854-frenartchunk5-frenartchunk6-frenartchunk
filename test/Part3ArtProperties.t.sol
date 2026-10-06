// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FrenRenderer} from "src/FrenRenderer.sol";
import {FrenArtIndex} from "src/FrenArtIndex.sol";
import {FrenArtRef, FrenRendererRef} from "./ref/FrenRendererRef.sol";
import {Part3Fixture} from "./helpers/Part3Fixture.sol";

/// @dev Exposes only the production reader; the oracle is the original binary art kit.
contract Part3EntryReader is FrenRenderer {
    constructor(address[7] memory c) FrenRenderer(c[0], c[1], c[2], c[3], c[4], c[5], c[6]) {}

    function entry(uint256 i) external view returns (bytes memory) {
        return _entry(i);
    }
}

contract Part3ArtPropertiesTest is Part3Fixture {
    Part3EntryReader internal reader;
    FrenRendererRef internal referenceRenderer;

    function setUp() public override {
        super.setUp();
        reader = new Part3EntryReader(chunks);
        FrenArtRef art = new FrenArtRef();
        string memory manifest = vm.readFile("script/art/data/manifest.json");
        string[] memory names = vm.parseJsonStringArray(manifest, ".layers");
        bytes[] memory data = new bytes[](names.length + 1);
        for (uint256 i; i < names.length; ++i) {
            data[i] = vm.readFileBinary(string.concat("script/art/data/layers/", names[i], ".bin"));
        }
        data[names.length] = vm.readFileBinary("script/art/data/palette.bin");
        address[] memory written = art.write(data);
        address[] memory layers = new address[](names.length);
        for (uint256 i; i < names.length; ++i) {
            layers[i] = written[i];
        }
        referenceRenderer = new FrenRendererRef(
            written[names.length],
            layers,
            vm.readFileBinary("script/art/data/tables.bin"),
            vm.readFileBinary("script/art/data/facetable.bin"),
            uint8(vm.parseJsonUint(manifest, ".shadow"))
        );
    }

    function test_AllLayersAndPaletteDecodeExactlyToTheArtKit() public view {
        string[] memory names = vm.parseJsonStringArray(vm.readFile("script/art/data/manifest.json"), ".layers");
        assertEq(names.length, 69);
        for (uint256 i; i < names.length; ++i) {
            assertEq(
                reader.entry(i), vm.readFileBinary(string.concat("script/art/data/layers/", names[i], ".bin")), names[i]
            );
        }
        assertEq(reader.entry(69), vm.readFileBinary("script/art/data/palette.bin"), "palette");
    }

    function test_ChunkSizesHashesAndStopPrefixMatchTheIndex() public view {
        bytes memory sizes = FrenArtIndex.CHUNK_SIZES;
        bytes memory hashes = FrenArtIndex.CHUNK_HASHES;
        for (uint256 i; i < 7; ++i) {
            bytes memory runtime = chunks[i].code;
            assertEq(runtime[0], bytes1(0), "missing STOP");
            assertEq(runtime.length, (uint256(uint8(sizes[i * 2])) << 8) | uint8(sizes[i * 2 + 1]));
            assertLe(runtime.length, 24_576);
            bytes32 expected;
            assembly ("memory-safe") {
                expected := mload(add(add(hashes, 32), mul(i, 32)))
            }
            assertEq(chunks[i].codehash, expected);
        }
    }

    function test_Chunk7FramesContainExactArtAndOnlyZeroPadding() public view {
        bytes memory raw = chunks[6].code;
        bytes memory art = bytes.concat(
            vm.readFileBinary("script/art/data/layers/bg8.bin"),
            vm.readFileBinary("script/art/data/layers/bg9.bin"),
            vm.readFileBinary("script/art/data/palette.bin")
        );
        assertEq(raw.length, 1 + ((art.length + 31) / 32) * 33);
        assertEq(raw[0], bytes1(0));
        uint256 cursor;
        for (uint256 frame = 1; frame < raw.length; frame += 33) {
            assertEq(raw[frame], bytes1(0x7f), "frame must start with PUSH32");
            for (uint256 j = 1; j <= 32; ++j) {
                assertEq(raw[frame + j], cursor < art.length ? art[cursor] : bytes1(0), "frame payload/padding");
                ++cursor;
            }
        }
    }

    function test_ReaderRejectsShortPlainAndFramedRuntimes() public {
        // Last entry of every chunk exercises the size boundary, including both framed chunks.
        // Etching after deployment is fault injection, not an assumption that mainnet code can mutate.
        uint256[7] memory lastEntries = [uint256(13), 24, 36, 60, 63, 66, 69];
        for (uint256 i; i < 7; ++i) {
            bytes memory original = chunks[i].code;
            bytes memory shortened = new bytes(original.length - 1);
            for (uint256 j; j < shortened.length; ++j) {
                shortened[j] = original[j];
            }
            vm.etch(chunks[i], shortened);
            vm.expectRevert(FrenRenderer.Missing.selector);
            reader.entry(lastEntries[i]);
            vm.etch(chunks[i], original);
        }
    }

    function _le(bytes memory b, uint256 offset, uint256 size) internal pure returns (uint256 value) {
        for (uint256 i; i < size; ++i) {
            value |= uint256(uint8(b[offset + i])) << (8 * i);
        }
    }

    function _assertBitmap(uint24 combo, uint256 seed) internal view {
        bytes memory cv = renderer.canvas(combo, seed);
        assertEq(cv, referenceRenderer.canvas(combo, seed), "canvas differs from launch renderer");
        bytes memory bitmap = renderer.bmp(combo, seed);
        assertEq(cv.length, 84 * 84);
        assertEq(bitmap.length, 1078 + 84 * 84);
        assertEq(_le(bitmap, 0, 2), 0x4d42, "BMP signature");
        assertEq(_le(bitmap, 2, 4), bitmap.length, "file size");
        assertEq(_le(bitmap, 6, 4), 0, "reserved");
        assertEq(_le(bitmap, 10, 4), 1078, "pixel offset");
        assertEq(_le(bitmap, 14, 4), 40, "DIB size");
        assertEq(_le(bitmap, 18, 4), 84, "width");
        assertEq(_le(bitmap, 22, 4), 84, "height");
        assertEq(_le(bitmap, 26, 2), 1, "planes");
        assertEq(_le(bitmap, 28, 2), 8, "bits per pixel");
        assertEq(_le(bitmap, 30, 4), 0, "compression");
        assertEq(_le(bitmap, 34, 4), cv.length, "pixel data length");
        assertEq(_le(bitmap, 46, 4), 256, "palette size");
        bytes memory palette = vm.readFileBinary("script/art/data/palette.bin");
        for (uint256 i; i < palette.length; ++i) {
            assertEq(bitmap[54 + i], palette[i], "palette byte");
        }
        // Decode bottom-up BMP pixels into the public top-down canvas, independently of _bmpOf/_copy.
        for (uint256 y; y < 84; ++y) {
            for (uint256 x; x < 84; ++x) {
                assertEq(bitmap[1078 + y * 84 + x], cv[(83 - y) * 84 + x], "BMP pixel orientation");
            }
        }
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzz_ValidCombosMatchReferenceAndRoundTripBMP(uint256 entropy, uint256 seed) public view {
        _assertBitmap(_validCombo(entropy), seed);
    }

    function test_ValidTraitAndSeedBoundaries() public view {
        uint24 last = uint24(2 | 12 << 2 | 3 << 6 | 2 << 8 | 5 << 10 | 2 << 13 | 9 << 15 | 15 << 19);
        _assertBitmap(0, 0);
        _assertBitmap(0, 1);
        _assertBitmap(last, type(uint256).max);
        // Every seed window edge, including the largest x and y offsets (36, 36).
        _assertBitmap(last, 36);
        _assertBitmap(last, 37);
        _assertBitmap(last, 36 * 256 + 33);
    }

    /// forge-config: default.fuzz.runs = 16
    function testFuzz_MetadataAndUnrevealedFramesMatchReference(uint256 tokenId, uint256 entropy, uint256 seed)
        public
        view
    {
        uint24 combo = _validCombo(entropy);
        assertEq(renderer.tokenURI(tokenId, combo, seed), referenceRenderer.tokenURI(tokenId, combo, seed));
        bytes memory frames = renderer.unrevealed(tokenId);
        assertEq(frames.length, 4 * 84 * 84);
        assertEq(frames, referenceRenderer.unrevealed(tokenId));
        assertEq(renderer.pendingURI(tokenId), referenceRenderer.pendingURI(tokenId));
    }

    function test_PendingMetadataAtTokenIdBoundaries() public view {
        uint256[4] memory ids = [uint256(0), 1, 2222, type(uint256).max];
        for (uint256 i; i < ids.length; ++i) {
            assertEq(renderer.pendingURI(ids[i]), referenceRenderer.pendingURI(ids[i]));
        }
    }
}

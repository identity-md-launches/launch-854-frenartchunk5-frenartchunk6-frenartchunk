// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FrenRenderer} from "src/FrenRenderer.sol";

/// @dev Offline dependencies are the repository runtimes at the requested mainnet addresses.
/// This does not claim to verify mainnet state; the existing fork suite does that separately.
abstract contract Part3Fixture is Test {
    address[7] internal chunks;
    FrenRenderer internal renderer;

    function setUp() public virtual {
        chunks[0] = 0xa92dAcfF6d6fcC218ADe20eD24857376BD8eBE81;
        chunks[1] = 0x9666A481e20F1dB59EEbD6c43D11Ae3505468c92;
        chunks[2] = 0x71BdEB749b3ee428730eBB3E9b34B03A99D82356;
        chunks[3] = 0x0C344484D960B8474a1EdcB5A5128e8D9C9F6B4d;
        for (uint256 i; i < 4; ++i) {
            address local = deployCode(string.concat("FrenArtChunks.sol:FrenArtChunk", vm.toString(i + 1)));
            vm.etch(chunks[i], local.code);
        }
        // No constructor arguments, in launch order: 5, 6, 7, then the renderer.
        for (uint256 i = 4; i < 7; ++i) {
            chunks[i] = deployCode(string.concat("FrenArtChunks.sol:FrenArtChunk", vm.toString(i + 1)));
        }
        renderer = _deployRenderer(chunks);
    }

    function _deployRenderer(address[7] memory c) internal returns (FrenRenderer) {
        return new FrenRenderer(c[0], c[1], c[2], c[3], c[4], c[5], c[6]);
    }

    function _validCombo(uint256 entropy) internal pure returns (uint24 combo) {
        uint256[8] memory shifts = [uint256(0), 2, 6, 8, 10, 13, 15, 19];
        uint256[8] memory maxima = [uint256(2), 12, 3, 2, 5, 2, 9, 15];
        for (uint256 i; i < 8; ++i) {
            combo |= uint24(bound(uint8(entropy >> (i * 8)), 0, maxima[i]) << shifts[i]);
        }
    }
}

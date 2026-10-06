// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FrenRenderer} from "../src/FrenRenderer.sol";
import {FrenArtChunk5, FrenArtChunk6, FrenArtChunk7} from "../src/FrenArtChunks.sol";

/// @notice On a mainnet fork: the chunks the swarm has deployed (IMD launches 819 and 838: FrenArtChunk1-4), with the
///         rest deployed here until launch 3 lands, draw every reference bitmap exactly. MAINNET_RPC_URL; skips without.
contract OnChainChunksForkTest is Test {
    address constant CHUNK1 = 0xa92dAcfF6d6fcC218ADe20eD24857376BD8eBE81; // launch 819, tx 0x7b6503…012d
    address constant CHUNK2 = 0x9666A481e20F1dB59EEbD6c43D11Ae3505468c92;
    address constant CHUNK3 = 0x71BdEB749b3ee428730eBB3E9b34B03A99D82356; // launch 838, tx 0xcbee71…0903
    address constant CHUNK4 = 0x0C344484D960B8474a1EdcB5A5128e8D9C9F6B4d;

    function test_swarmChunksDrawTheReference() public {
        string memory rpc_ = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc_).length == 0) vm.skip(true);
        vm.createSelectFork(rpc_);
        address c3 = CHUNK3;
        address c4 = CHUNK4;
        FrenRenderer r = new FrenRenderer(
            CHUNK1, CHUNK2, c3, c4, address(new FrenArtChunk5()), address(new FrenArtChunk6()), address(new FrenArtChunk7())
        );
        string memory exp = vm.readFile("script/art/data/expected.json");
        uint256 i;
        for (; vm.keyExistsJson(exp, string.concat(".[", vm.toString(i), "]")); ++i) {
            string memory k = string.concat(".[", vm.toString(i), "]");
            uint24 combo = uint24(vm.parseJsonUint(exp, string.concat(k, ".combo")));
            uint256 seed = vm.parseUint(vm.parseJsonString(exp, string.concat(k, ".seed")));
            assertEq(sha256(r.bmp(combo, seed)), vm.parseJsonBytes32(exp, string.concat(k, ".bmpSha256")), "bitmap");
        }
        assertGe(i, 6);
        assertEq(bytes(r.tokenURI(1, 0xbd59c, 42))[0], "d");
    }
}

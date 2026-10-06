// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FrenRenderer} from "src/FrenRenderer.sol";
import {Part3Fixture} from "./helpers/Part3Fixture.sol";

/// @dev STOP data contracts can receive unsolicited ETH. They have no balances owed to users,
/// withdrawal API, or treasury role. Track transfers only to test value conservation and inertness.
contract Part3CallHandler is Test {
    address[7] public chunks;
    address[4] public actors;
    uint256[7] public received;
    FrenRenderer public immutable renderer;
    bytes32 public immutable initialBitmap;

    constructor(address[7] memory c, FrenRenderer r) {
        chunks = c;
        renderer = r;
        initialBitmap = keccak256(r.bmp(0, 0));
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = address(uint160(0xA000 + i));
            vm.deal(actors[i], 100 ether);
        }
    }

    function callChunk(uint8 slot, uint8 actorIndex, uint96 amount, bytes calldata data) external {
        uint256 i = bound(slot, 0, 6);
        address actor = actors[bound(actorIndex, 0, 3)];
        uint256 value = bound(amount, 0, 1 ether);
        if (value > actor.balance) value = actor.balance;
        bytes memory payload = data[:bound(data.length, 0, data.length > 128 ? 128 : data.length)];
        uint256 before = actor.balance;
        vm.prank(actor);
        (bool ok, bytes memory result) = chunks[i].call{value: value}(payload);
        assertTrue(ok, "STOP call failed");
        assertEq(result.length, 0, "STOP call returned data");
        assertEq(actor.balance, before - value, "caller value delta");
        received[i] += value;
    }

    function probeChunk(uint8 slot, uint8 actorIndex, uint8 action, bytes32 argument) external {
        bytes[4] memory payloads = [
            abi.encodeWithSignature("withdraw()"),
            abi.encodeWithSignature("transfer(address,uint256)", address(this), uint256(argument)),
            abi.encodeWithSignature("initialize(address)", address(this)),
            abi.encodeWithSignature("selfdestruct(address)", address(this))
        ];
        address chunk = chunks[bound(slot, 0, 6)];
        bytes memory payload = payloads[bound(action, 0, 3)];
        vm.prank(actors[bound(actorIndex, 0, 3)]);
        (bool ok, bytes memory result) = chunk.call(payload);
        assertTrue(ok, "STOP is independent of selector");
        assertEq(result.length, 0);
    }

    function rejectRendererValue(uint8 actorIndex, uint96 amount, bool emptyCalldata) external {
        address actor = actors[bound(actorIndex, 0, 3)];
        uint256 value = bound(amount, 1, 1 ether);
        bytes memory payload = emptyCalldata ? bytes("") : abi.encodeCall(renderer.chunk1, ());
        uint256 before = actor.balance;
        vm.prank(actor);
        (bool ok, bytes memory result) = address(renderer).call{value: value}(payload);
        assertFalse(ok, "renderer accepted value");
        assertEq(result.length, 0);
        assertEq(actor.balance, before, "rejected call spent value");
    }

    function renderAfterCalls(uint8 actorIndex) external {
        vm.prank(actors[bound(actorIndex, 0, 3)]);
        assertEq(keccak256(renderer.bmp(0, 0)), initialBitmap, "call sequence changed the art");
    }
}

/// forge-config: default.invariant.runs = 128
/// forge-config: default.invariant.depth = 32
/// forge-config: default.invariant.fail-on-revert = true
contract Part3InvariantTest is Part3Fixture {
    Part3CallHandler internal handler;
    bytes32[7] internal originalHashes;
    bytes32 internal rendererHash;

    function setUp() public override {
        super.setUp();
        for (uint256 i; i < 7; ++i) {
            originalHashes[i] = chunks[i].codehash;
        }
        rendererHash = address(renderer).codehash;
        handler = new Part3CallHandler(chunks, renderer);
        // Explicit targets prevent the invariant runner from calling Test cheatcode helpers or setup contracts.
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.callChunk.selector;
        selectors[1] = handler.probeChunk.selector;
        selectors[2] = handler.rejectRendererValue.selector;
        selectors[3] = handler.renderAfterCalls.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        // Nonzero starting transfers make the balance invariant meaningful even in a short campaign.
        for (uint8 i; i < 7; ++i) {
            handler.callChunk(i, i % 4, 1, hex"");
        }
    }

    function invariant_ConservesValueAcrossActorsAndDataContracts() public view {
        uint256 total;
        for (uint256 i; i < 7; ++i) {
            assertEq(chunks[i].balance, handler.received(i), "chunk spent or lost received ETH");
            total += chunks[i].balance;
        }
        for (uint256 i; i < 4; ++i) {
            total += handler.actors(i).balance;
        }
        assertEq(total, 400 ether, "value conservation");
        assertEq(address(renderer).balance, 0, "renderer accumulated value through calls");
    }

    function invariant_CodeAndDependenciesNeverChange() public view {
        for (uint256 i; i < 7; ++i) {
            assertEq(chunks[i].codehash, originalHashes[i], "art runtime changed");
        }
        assertEq(address(renderer).codehash, rendererHash, "renderer runtime changed");
        assertEq(renderer.chunk1(), chunks[0]);
        assertEq(renderer.chunk2(), chunks[1]);
        assertEq(renderer.chunk3(), chunks[2]);
        assertEq(renderer.chunk4(), chunks[3]);
        assertEq(renderer.chunk5(), chunks[4]);
        assertEq(renderer.chunk6(), chunks[5]);
        assertEq(renderer.chunk7(), chunks[6]);
    }

    function test_ZeroOneWeiAndWholeActorBalanceSequence() public {
        handler.callChunk(4, 0, 0, hex"");
        handler.callChunk(5, 0, 1, hex"ff");
        // Drain this actor through bounded calls, then repeat operations from the empty account.
        for (uint256 i; i < 100; ++i) {
            handler.callChunk(6, 0, uint96(1 ether), hex"f4f2ff");
        }
        assertEq(handler.actors(0).balance, 0);
        handler.callChunk(6, 0, 1, hex"");
        handler.probeChunk(6, 0, 0, bytes32(0));
        handler.rejectRendererValue(1, 1, false);
        handler.renderAfterCalls(0);
        invariant_ConservesValueAcrossActorsAndDataContracts();
        invariant_CodeAndDependenciesNeverChange();
    }
}

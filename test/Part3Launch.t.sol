// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FrenRenderer} from "../src/FrenRenderer.sol";

/// @dev Test-only factory: the protected probe's zero-value CREATE2 deployment, batched in launch order.
contract Part3DeploymentProbe {
    function deploy(bytes[] memory codes) external returns (address[] memory deployed) {
        deployed = new address[](codes.length);
        for (uint256 i; i < codes.length; ++i) {
            bytes memory code = codes[i];
            require(code.length > 0 && code.length <= 49_152, "invalid init code");
            address application;
            assembly ("memory-safe") {
                application := create2(0, add(code, 32), mload(code), i)
            }
            require(application != address(0) && application.code.length > 0, "application constructor failed");
            deployed[i] = application;
        }
    }
}

/// @dev Measure a nested call so Foundry's top-level isolation cannot add intrinsic gas to this sample.
contract Part3GasMeter {
    function measure(Part3DeploymentProbe factory, bytes[] memory codes)
        external
        returns (address[] memory deployed, uint256 used)
    {
        uint256 beforeGas = gasleft();
        deployed = factory.deploy(codes);
        used = beforeGas - gasleft();
    }
}

/// @notice Offline rehearsal of part 3 using the four requested dependency addresses.
/// @dev Etched code comes from this repository, not mainnet; OnChainChunks.fork.t.sol checks live dependencies.
contract Part3LaunchTest is Test {
    address constant CHUNK1 = 0xa92dAcfF6d6fcC218ADe20eD24857376BD8eBE81;
    address constant CHUNK2 = 0x9666A481e20F1dB59EEbD6c43D11Ae3505468c92;
    address constant CHUNK3 = 0x71BdEB749b3ee428730eBB3E9b34B03A99D82356;
    address constant CHUNK4 = 0x0C344484D960B8474a1EdcB5A5128e8D9C9F6B4d;

    address[] applications;
    address[4] predicted;
    FrenRenderer renderer;
    uint256 deploymentGas;
    uint256 intrinsicGas;

    function setUp() public {
        address[4] memory existing = [CHUNK1, CHUNK2, CHUNK3, CHUNK4];
        for (uint256 i; i < existing.length; ++i) {
            address local = deployCode(string.concat("FrenArtChunks.sol:FrenArtChunk", vm.toString(i + 1)));
            vm.etch(existing[i], local.code);
        }

        Part3DeploymentProbe factory = new Part3DeploymentProbe();
        Part3GasMeter meter = new Part3GasMeter();
        bytes[] memory codes = new bytes[](4);
        for (uint256 i; i < 3; ++i) {
            codes[i] = vm.getCode(string.concat("FrenArtChunks.sol:FrenArtChunk", vm.toString(i + 5)));
            predicted[i] = _predict(address(factory), bytes32(i), codes[i]);
        }
        codes[3] = bytes.concat(
            vm.getCode("FrenRenderer.sol:FrenRenderer"),
            abi.encode(CHUNK1, CHUNK2, CHUNK3, CHUNK4, predicted[0], predicted[1], predicted[2])
        );
        predicted[3] = _predict(address(factory), bytes32(uint256(3)), codes[3]);
        bytes memory payload = abi.encodeCall(factory.deploy, (codes));
        intrinsicGas = 21_000;
        for (uint256 i; i < payload.length; ++i) {
            intrinsicGas += payload[i] == 0 ? 4 : 16;
        }
        (address[] memory deployed, uint256 used) = meter.measure(factory, codes);
        deploymentGas = used;
        applications = deployed;
        renderer = FrenRenderer(deployed[3]);
    }

    function _predict(address factory, bytes32 salt, bytes memory code) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), factory, salt, keccak256(code))))));
    }

    function test_Create2DeploysPart3WithTheRequestedArguments() public view {
        assertEq(applications.length, 4);
        for (uint256 i; i < applications.length; ++i) {
            assertEq(applications[i], predicted[i]);
        }
        assertEq(renderer.chunk1(), CHUNK1);
        assertEq(renderer.chunk2(), CHUNK2);
        assertEq(renderer.chunk3(), CHUNK3);
        assertEq(renderer.chunk4(), CHUNK4);
        assertEq(renderer.chunk5(), applications[0]);
        assertEq(renderer.chunk6(), applications[1]);
        assertEq(renderer.chunk7(), applications[2]);

        string memory expected = vm.readFile("script/art/data/expected.json");
        uint256 count;
        for (; vm.keyExistsJson(expected, string.concat(".[", vm.toString(count), "]")); ++count) {
            string memory key = string.concat(".[", vm.toString(count), "]");
            uint24 combo = uint24(vm.parseJsonUint(expected, string.concat(key, ".combo")));
            uint256 seed = vm.parseUint(vm.parseJsonString(expected, string.concat(key, ".seed")));
            assertEq(
                sha256(renderer.bmp(combo, seed)),
                vm.parseJsonBytes32(expected, string.concat(key, ".bmpSha256")),
                "factory-deployed renderer changed the art"
            );
        }
        assertGe(count, 6);
    }

    function test_AllPart3RuntimesPassAdmission() public view {
        for (uint256 i; i < applications.length; ++i) {
            bytes memory code = applications[i].code;
            assertGt(code.length, 0, "missing runtime");
            assertLe(code.length, 24_576, "runtime exceeds EIP-170");
            for (uint256 j; j < code.length; ++j) {
                uint8 op = uint8(code[j]);
                if (op >= 0x60 && op <= 0x7f) {
                    j += op - 0x5f;
                    continue;
                }
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden application opcode");
            }
        }
    }

    function test_Part3Create2GasIsMeteredAndWithinLocalBudget() public {
        uint256 runtimeBytes;
        for (uint256 i; i < applications.length; ++i) {
            runtimeBytes += applications[i].code.length;
        }
        assertGe(deploymentGas, 200 * runtimeBytes, "CREATE2 code deposit is not metered");
        // Intrinsic gas is counted once, with exact zero/nonzero calldata pricing. The existing 95% budget
        // bounds this local rehearsal only: it neither measures the production factory nor validates the
        // deployer's buffered gas LIMIT. That unresolved submission requirement is in .imd-findings.json.
        uint256 total = deploymentGas + intrinsicGas;
        emit log_named_uint("part 3 local CREATE2 gas (with intrinsic)", total);
        assertLt(total, uint256(1 << 24) * 95 / 100, "local creation gas budget");
    }
}

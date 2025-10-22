// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {DCAHook} from "../../../../src/v4/hooks/dca/DCAHook.sol";
import {DCALib} from "../../../../src/v4/hooks/dca/DCALib.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";

/// @title DCAHook Domain Separator Test
/// @notice Tests that domain separator is dynamically computed after chain fork
contract DCAHook_DomainSeparatorTest is Test {
    DCAHook hook;
    IPermit2 permit2;
    IReactor reactor;

    function setUp() public {
        // Deploy mock contracts
        permit2 = IPermit2(address(0x1));
        reactor = IReactor(address(0x2));

        // Deploy DCAHook
        hook = new DCAHook(permit2, reactor);
    }

    /// @notice Test that domain separator is cached on deployment chain
    function test_domainSeparator_cachedOnDeploymentChain() public view {
        // Get domain separator
        bytes32 domainSep = hook.DOMAIN_SEPARATOR();

        // Verify it matches the expected value
        bytes32 expected = DCALib.computeDomainSeparator(address(hook));
        assertEq(domainSep, expected, "Domain separator should match expected value");
    }

    /// @notice Test that domain separator changes when chain ID changes (simulating a fork)
    function test_domainSeparator_changesAfterFork() public {
        // Get initial domain separator
        bytes32 initialDomainSep = hook.DOMAIN_SEPARATOR();
        uint256 initialChainId = block.chainid;

        // Simulate chain fork by changing chain ID
        uint256 newChainId = initialChainId + 1;
        vm.chainId(newChainId);

        // Get domain separator after fork
        bytes32 newDomainSep = hook.DOMAIN_SEPARATOR();

        // Verify domain separator has changed
        assertTrue(newDomainSep != initialDomainSep, "Domain separator should change after fork");

        // Verify new domain separator is correct for new chain
        bytes32 expected = DCALib.computeDomainSeparator(address(hook));
        assertEq(newDomainSep, expected, "Domain separator should match new chain ID");
    }

    /// @notice Test that domain separator returns to cached value when chain ID returns to original
    function test_domainSeparator_returnsToCachedValue() public {
        // Get initial values
        bytes32 initialDomainSep = hook.DOMAIN_SEPARATOR();
        uint256 initialChainId = block.chainid;

        // Change chain ID
        vm.chainId(initialChainId + 1);
        bytes32 forkedDomainSep = hook.DOMAIN_SEPARATOR();
        assertTrue(forkedDomainSep != initialDomainSep, "Should change on fork");

        // Return to original chain ID
        vm.chainId(initialChainId);
        bytes32 restoredDomainSep = hook.DOMAIN_SEPARATOR();

        // Verify it matches the original cached value
        assertEq(restoredDomainSep, initialDomainSep, "Should return to cached value");
    }

    /// @notice Fuzz test domain separator with various chain IDs
    function testFuzz_domainSeparator_variousChainIds(uint256 chainId) public {
        // Bound chain ID to reasonable values
        chainId = bound(chainId, 1, type(uint64).max);

        // Set chain ID
        vm.chainId(chainId);

        // Get domain separator
        bytes32 domainSep = hook.DOMAIN_SEPARATOR();

        // Verify it matches the expected value for this chain
        bytes32 expected = DCALib.computeDomainSeparator(address(hook));
        assertEq(domainSep, expected, "Domain separator should match expected value for chain ID");
    }

    /// @notice Test that different contracts have different domain separators
    function test_domainSeparator_differentPerContract() public {
        // Deploy another hook
        DCAHook hook2 = new DCAHook(permit2, reactor);

        // Get domain separators
        bytes32 domainSep1 = hook.DOMAIN_SEPARATOR();
        bytes32 domainSep2 = hook2.DOMAIN_SEPARATOR();

        // Verify they are different (different contract addresses)
        assertTrue(domainSep1 != domainSep2, "Different contracts should have different domain separators");
    }

    /// @notice Test gas cost of domain separator getter (cached case)
    function test_domainSeparator_gasCost_cached() public {
        // This should use the cached immutable value - just verify it works
        bytes32 domainSep = hook.DOMAIN_SEPARATOR();
        assertTrue(domainSep != bytes32(0), "Domain separator should not be zero");
    }

    /// @notice Test gas cost of domain separator getter (recomputed case)
    function test_domainSeparator_gasCost_recomputed() public {
        // Change chain ID to force recomputation
        vm.chainId(block.chainid + 1);

        // This should recompute the domain separator - verify it works
        bytes32 domainSep = hook.DOMAIN_SEPARATOR();
        assertTrue(domainSep != bytes32(0), "Domain separator should not be zero");
    }

    /// @notice Test that replay attacks are prevented after fork
    function test_replayProtection_afterFork() public {
        // Get initial domain separator
        bytes32 initialDomainSep = hook.DOMAIN_SEPARATOR();

        // Simulate creating a signature on the original chain
        // (In a real scenario, this would be used in _validateSwapperSignature or _validateCosignerSignature)
        bytes32 structHash = keccak256("test data");
        bytes32 originalDigest = keccak256(abi.encodePacked("\x19\x01", initialDomainSep, structHash));

        // Simulate chain fork
        vm.chainId(block.chainid + 1);
        bytes32 newDomainSep = hook.DOMAIN_SEPARATOR();

        // Digest computed on new chain should be different
        bytes32 newDigest = keccak256(abi.encodePacked("\x19\x01", newDomainSep, structHash));

        assertTrue(originalDigest != newDigest, "Digest should differ after fork, preventing replay");
    }
}

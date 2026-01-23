// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../../../util/DeployPermit2.sol";

import {DCAHookHarness} from "./DCAHookHarness.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";

import {DCAIntent, DCAOrderCosignerData, OutputAllocation, PrivateIntent, FeedInfo} from "../../../../src/v4/hooks/dca/DCAStructs.sol";
import {OutputToken} from "../../../../src/base/ReactorStructs.sol";
import {IDCAHook} from "../../../../src/v4/interfaces/IDCAHook.sol";

contract DCAHook_validateOutputDistributionTest is Test, DeployPermit2 {
    DCAHookHarness hook;
    IPermit2 permit2;

    address constant REACTOR_ADDRESS = address(0x2345);
    IReactor constant REACTOR = IReactor(REACTOR_ADDRESS);

    address constant SWAPPER = address(0x1234);
    uint96 constant NONCE = 42;
    address constant COSIGNER = address(0x5678);
    address constant RECIPIENT_A = address(0xAAAA);
    address constant RECIPIENT_B = address(0xBBBB);

    function setUp() public {
        permit2 = IPermit2(deployPermit2());
        hook = new DCAHookHarness(permit2, REACTOR);
    }

    function _createExactOutIntent() internal view returns (DCAIntent memory) {
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({recipient: RECIPIENT_A, basisPoints: 5000});
        allocations[1] = OutputAllocation({recipient: RECIPIENT_B, basisPoints: 5000});

        PrivateIntent memory privateIntent = PrivateIntent({
            totalAmount: 0, exactFrequency: 0, numChunks: 0, salt: bytes32(0), oracleFeeds: new FeedInfo[](0)
        });

        return DCAIntent({
            swapper: SWAPPER,
            nonce: NONCE,
            chainId: block.chainid,
            hookAddress: address(hook),
            isExactIn: false,
            inputToken: address(0x1111),
            outputToken: address(0x2222),
            cosigner: COSIGNER,
            minPeriod: 0,
            maxPeriod: 0,
            minChunkSize: 1,
            maxChunkSize: 10_000,
            minPrice: 0,
            deadline: block.timestamp + 1 days,
            outputAllocations: allocations,
            privateIntent: privateIntent
        });
    }

    function test_validateOutputDistribution_exactOut_remainderAssignedToFirstMaxBpsRecipient() public view {
        DCAIntent memory intent = _createExactOutIntent();
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, 101, 0, 0);

        // 50/50 split with odd total: remainder should go to first max-bps recipient (RECIPIENT_A).
        OutputToken[] memory outputs = new OutputToken[](2);
        outputs[0] = OutputToken({token: intent.outputToken, amount: 51, recipient: RECIPIENT_A});
        outputs[1] = OutputToken({token: intent.outputToken, amount: 50, recipient: RECIPIENT_B});

        hook.validateOutputDistribution(intent, cosignerData, outputs);
    }

    function test_validateOutputDistribution_exactOut_remainderOnOtherRecipient_reverts() public {
        DCAIntent memory intent = _createExactOutIntent();
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, 101, 0, 0);

        // Remainder incorrectly assigned to RECIPIENT_B should revert.
        OutputToken[] memory outputs = new OutputToken[](2);
        outputs[0] = OutputToken({token: intent.outputToken, amount: 50, recipient: RECIPIENT_A});
        outputs[1] = OutputToken({token: intent.outputToken, amount: 51, recipient: RECIPIENT_B});

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.AllocationMismatch.selector, RECIPIENT_A, 50, 51));
        hook.validateOutputDistribution(intent, cosignerData, outputs);
    }

    /// For EXACT_IN, expected allocations are floored and checked per-recipient with ±1 tolerance,
    /// but there's no requirement that *all* output goes only to allocation recipients.
    /// A remainder can be swept to an unallocated recipient without reverting.
    function test_validateOutputDistribution_exactIn_allowsUnallocatedRemainderSweep_shouldRevert() public {
        address attacker = address(0xBAD); // NOT allocated

        OutputAllocation[] memory allocs = new OutputAllocation[](2);
        allocs[0] = OutputAllocation({recipient: RECIPIENT_A, basisPoints: 5000});
        allocs[1] = OutputAllocation({recipient: RECIPIENT_B, basisPoints: 5000});

        DCAIntent memory intent;
        intent.isExactIn = true;
        intent.outputAllocations = allocs;

        // totalOutput = 3
        // expected floors are 1 and 1; the "extra" 1 can be sent to attacker.
        OutputToken[] memory outputs = new OutputToken[](3);
        outputs[0] = OutputToken({token: address(0xBEEF), amount: 1, recipient: RECIPIENT_A});
        outputs[1] = OutputToken({token: address(0xBEEF), amount: 1, recipient: RECIPIENT_B});
        outputs[2] = OutputToken({token: address(0xBEEF), amount: 1, recipient: attacker});

        DCAOrderCosignerData memory cd;
        cd.limitAmount = 0; // don't fail on totalOutput < limit

        // Correct behavior would revert
        vm.expectRevert();
        hook.validateOutputDistribution(intent, cd, outputs);
    }
}

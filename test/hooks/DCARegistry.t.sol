// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DCARegistry} from "../../src/validation/DCARegistry.sol";
import {IDCARegistry} from "../../src/interfaces/IDCARegistry.sol";
import {IERC1271} from "permit2/src/interfaces/IERC1271.sol";
import {IPreExecutionHook} from "../../src/interfaces/IPreExecutionHook.sol";
import {IValidationCallback} from "../../src/interfaces/IValidationCallback.sol";
import {UnifiedReactor} from "../../src/reactors/UnifiedReactor.sol";
import {PriorityAuctionResolver} from "../../src/resolvers/PriorityAuctionResolver.sol";
import {ResolvedOrderV2, SignedOrder, OrderInfoV2, InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {DCAIntentSignature} from "../util/DCAIntentSignature.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {Permit2LibV2} from "../../src/lib/Permit2LibV2.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract DCARegistryTest is Test, DCAIntentSignature, PermitSignature, DeployPermit2 {
    using Permit2LibV2 for ResolvedOrderV2;

    // Helper functions for creating inputs and outputs
    function toInput(MockERC20 token, uint256 amount) internal pure returns (InputToken memory) {
        return InputToken({token: ERC20(address(token)), amount: amount, maxAmount: amount});
    }

    function toOutput(MockERC20 token, uint256 amount) internal view returns (OutputToken memory) {
        return OutputToken({token: address(token), amount: amount, recipient: address(this)});
    }

    DCARegistry dcaRegistry;
    UnifiedReactor reactor;
    PriorityAuctionResolver resolver;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    IPermit2 permit2;

    uint256 constant SWAPPER_PRIVATE_KEY = 0x12341234;
    uint256 constant COSIGNER_PRIVATE_KEY = 0x56785678;
    address swapper;
    address cosigner;
    address filler = address(0x1111);

    bytes4 constant MAGICVALUE = 0x1626ba7e;

    function setUp() public {
        // Deploy permit2
        permit2 = IPermit2(deployPermit2());

        // Set up accounts
        swapper = vm.addr(SWAPPER_PRIVATE_KEY);
        cosigner = vm.addr(COSIGNER_PRIVATE_KEY);

        // Deploy contracts
        dcaRegistry = new DCARegistry();
        reactor = new UnifiedReactor(permit2, address(this));
        resolver = new PriorityAuctionResolver(permit2);

        // Deploy tokens
        tokenIn = new MockERC20("Input Token", "IN", 18);
        tokenOut = new MockERC20("Output Token", "OUT", 18);

        // Mint tokens to swapper
        tokenIn.mint(swapper, 10000e18);

        // Label addresses for debugging
        vm.label(address(dcaRegistry), "DCARegistry");
        vm.label(address(reactor), "UnifiedReactor");
        vm.label(address(resolver), "PriorityAuctionResolver");
        vm.label(swapper, "Swapper");
        vm.label(cosigner, "Cosigner");
        vm.label(filler, "Filler");
    }

    // ===== BASIC EIP-1271 SIGNATURE VALIDATION TESTS =====

    function test_EIP1271_isValidSignature_beforePreExecutionHook() public {
        bytes32 orderHash = keccak256("test order hash");

        // Should return 0 before pre-execution hook
        bytes4 result = dcaRegistry.isValidSignature(orderHash, "");
        assertEq(result, bytes4(0), "Should return 0 for inactive order");
    }

    function test_EIP1271_isValidSignature_afterPreExecutionHook() public {
        // Create DCA intent
        IDCARegistry.DCAIntent memory intent =
            createPublicDCAIntent(address(tokenIn), address(tokenOut), cosigner, keccak256("private params"));

        // Create cosigner data with actual swapper address
        IDCARegistry.DCAOrderCosignerData memory cosignerData =
            createBasicCosignerData(swapper, 500e18, 450e18, keccak256("order nonce"));

        // Create validation data
        IDCARegistry.DCAValidationData memory validationData =
            createSignedDCAValidationData(intent, cosignerData, SWAPPER_PRIVATE_KEY, COSIGNER_PRIVATE_KEY, dcaRegistry);

        // Create a mock resolved order
        ResolvedOrderV2 memory order = ResolvedOrderV2({
            info: OrderInfoV2({
                reactor: reactor,
                swapper: address(dcaRegistry), // DCARegistry is the swapper
                nonce: 1,
                deadline: block.timestamp + 1 hours,
                preExecutionHook: IPreExecutionHook(address(dcaRegistry)),
                preExecutionHookData: abi.encode(validationData)
            }),
            input: toInput(tokenIn, 500e18),
            outputs: new OutputToken[](1),
            sig: "",
            hash: keccak256("test order hash"),
            auctionResolver: address(resolver)
        });
        order.outputs[0] = toOutput(tokenOut, 450e18);

        // Approve DCARegistry to spend swapper's tokens
        vm.prank(swapper);
        tokenIn.approve(address(dcaRegistry), 500e18);

        // Call pre-execution hook
        vm.prank(address(reactor));
        dcaRegistry.preExecutionHook(filler, order);

        // Now isValidSignature should return magic value
        bytes4 result = dcaRegistry.isValidSignature(order.hash, "");
        assertEq(result, MAGICVALUE, "Should return magic value for active order");
    }

    function test_markOrderComplete_clearsActiveHash() public {
        // First make an order active
        test_EIP1271_isValidSignature_afterPreExecutionHook();

        bytes32 orderHash = keccak256("test order hash");

        // Verify it's active
        bytes4 result = dcaRegistry.isValidSignature(orderHash, "");
        assertEq(result, MAGICVALUE, "Should be active before marking complete");

        // Mark complete
        dcaRegistry.markOrderComplete(orderHash);

        // Should no longer be active
        result = dcaRegistry.isValidSignature(orderHash, "");
        assertEq(result, bytes4(0), "Should not be active after marking complete");
    }

    // ===== PRE-EXECUTION HOOK TESTS =====

    function test_preExecutionHook_pullsTokensFromSwapper() public {
        // Create DCA intent
        IDCARegistry.DCAIntent memory intent =
            createPublicDCAIntent(address(tokenIn), address(tokenOut), cosigner, keccak256("private params"));

        // Create cosigner data with actual swapper address
        IDCARegistry.DCAOrderCosignerData memory cosignerData =
            createBasicCosignerData(swapper, 500e18, 450e18, keccak256("order nonce"));

        // Create validation data
        IDCARegistry.DCAValidationData memory validationData =
            createSignedDCAValidationData(intent, cosignerData, SWAPPER_PRIVATE_KEY, COSIGNER_PRIVATE_KEY, dcaRegistry);

        // Create a mock resolved order
        ResolvedOrderV2 memory order = ResolvedOrderV2({
            info: OrderInfoV2({
                reactor: reactor,
                swapper: address(dcaRegistry), // DCARegistry is the swapper
                nonce: 1,
                deadline: block.timestamp + 1 hours,
                preExecutionHook: IPreExecutionHook(address(dcaRegistry)),
                preExecutionHookData: abi.encode(validationData)
            }),
            input: toInput(tokenIn, 500e18),
            outputs: new OutputToken[](1),
            sig: "",
            hash: keccak256("test order hash"),
            auctionResolver: address(resolver)
        });
        order.outputs[0] = toOutput(tokenOut, 450e18);

        // Approve DCARegistry to spend swapper's tokens
        vm.prank(swapper);
        tokenIn.approve(address(dcaRegistry), 500e18);

        uint256 swapperBalanceBefore = tokenIn.balanceOf(swapper);
        uint256 registryBalanceBefore = tokenIn.balanceOf(address(dcaRegistry));

        // Call pre-execution hook
        vm.prank(address(reactor));
        dcaRegistry.preExecutionHook(filler, order);

        // Check tokens were transferred
        assertEq(tokenIn.balanceOf(swapper), swapperBalanceBefore - 500e18, "Swapper balance should decrease");
        assertEq(
            tokenIn.balanceOf(address(dcaRegistry)), registryBalanceBefore + 500e18, "Registry balance should increase"
        );
    }

    function test_preExecutionHook_validatesIntent() public {
        // Create DCA intent
        IDCARegistry.DCAIntent memory intent =
            createPublicDCAIntent(address(tokenIn), address(tokenOut), cosigner, keccak256("private params"));

        // Create cosigner data with wrong swapper address (should fail for new intent)
        IDCARegistry.DCAOrderCosignerData memory cosignerData = createBasicCosignerData(
            address(0), // Invalid swapper
            500e18,
            450e18,
            keccak256("order nonce")
        );

        // Create validation data
        IDCARegistry.DCAValidationData memory validationData =
            createSignedDCAValidationData(intent, cosignerData, SWAPPER_PRIVATE_KEY, COSIGNER_PRIVATE_KEY, dcaRegistry);

        // Create a mock resolved order
        ResolvedOrderV2 memory order = ResolvedOrderV2({
            info: OrderInfoV2({
                reactor: reactor,
                swapper: address(dcaRegistry),
                nonce: 1,
                deadline: block.timestamp + 1 hours,
                preExecutionHook: IPreExecutionHook(address(dcaRegistry)),
                preExecutionHookData: abi.encode(validationData)
            }),
            input: toInput(tokenIn, 500e18),
            outputs: new OutputToken[](1),
            sig: "",
            hash: keccak256("test order hash"),
            auctionResolver: address(resolver)
        });
        order.outputs[0] = toOutput(tokenOut, 450e18);

        // Should revert with invalid params
        vm.prank(address(reactor));
        vm.expectRevert(DCARegistry.InvalidDCAParams.selector);
        dcaRegistry.preExecutionHook(filler, order);
    }

    // ===== INTEGRATION TESTS =====

    function test_fullDCAFlow_withPermit2() public {
        // Create DCA intent
        IDCARegistry.DCAIntent memory intent =
            createPublicDCAIntent(address(tokenIn), address(tokenOut), cosigner, keccak256("private params"));

        // Create cosigner data
        IDCARegistry.DCAOrderCosignerData memory cosignerData =
            createBasicCosignerData(swapper, 500e18, 450e18, keccak256("order nonce"));

        // Create validation data
        IDCARegistry.DCAValidationData memory validationData =
            createSignedDCAValidationData(intent, cosignerData, SWAPPER_PRIVATE_KEY, COSIGNER_PRIVATE_KEY, dcaRegistry);

        // Approve tokens from swapper to DCARegistry
        vm.prank(swapper);
        tokenIn.approve(address(dcaRegistry), 500e18);

        // Also approve from DCARegistry to Permit2 for the permitWitnessTransferFrom
        vm.prank(address(dcaRegistry));
        tokenIn.approve(address(permit2), type(uint256).max);

        // Create order with DCARegistry as swapper
        ResolvedOrderV2 memory order = ResolvedOrderV2({
            info: OrderInfoV2({
                reactor: reactor,
                swapper: address(dcaRegistry), // DCARegistry is the swapper
                nonce: 1,
                deadline: block.timestamp + 1 hours,
                preExecutionHook: IPreExecutionHook(address(dcaRegistry)),
                preExecutionHookData: abi.encode(validationData)
            }),
            input: toInput(tokenIn, 500e18),
            outputs: new OutputToken[](1),
            sig: "", // Empty signature - EIP-1271 will validate
            hash: bytes32(0), // Will be set later
            auctionResolver: address(resolver)
        });
        order.outputs[0] = toOutput(tokenOut, 450e18);

        // Calculate order hash
        order.hash = keccak256(abi.encode(order));

        // The full flow would involve:
        // 1. Reactor calls preExecutionHook -> tokens pulled to DCARegistry
        // 2. Reactor calls permitWitnessTransferFrom -> EIP-1271 validates
        // 3. Tokens flow from DCARegistry to reactor/filler

        // For this test, we'll verify the pre-execution hook works
        vm.prank(address(reactor));
        dcaRegistry.preExecutionHook(filler, order);

        // Verify tokens were pulled
        assertEq(tokenIn.balanceOf(address(dcaRegistry)), 500e18, "DCARegistry should have tokens");

        // Verify order is active for EIP-1271
        assertEq(dcaRegistry.isValidSignature(order.hash, ""), MAGICVALUE, "Order should be active");
    }

    // ===== VALIDATION EDGE CASES =====

    function test_rejectInvalidSwapper() public {
        // Create DCA intent
        IDCARegistry.DCAIntent memory intent =
            createPublicDCAIntent(address(tokenIn), address(tokenOut), cosigner, keccak256("private params"));

        // Create cosigner data with zero address (invalid)
        IDCARegistry.DCAOrderCosignerData memory cosignerData = createBasicCosignerData(
            address(0), // Invalid swapper
            500e18,
            450e18,
            keccak256("order nonce")
        );

        // Create validation data (signature will be invalid since we're using wrong swapper)
        IDCARegistry.DCAValidationData memory validationData =
            createSignedDCAValidationData(intent, cosignerData, SWAPPER_PRIVATE_KEY, COSIGNER_PRIVATE_KEY, dcaRegistry);

        // Create order
        ResolvedOrderV2 memory order = ResolvedOrderV2({
            info: OrderInfoV2({
                reactor: reactor,
                swapper: address(dcaRegistry),
                nonce: 1,
                deadline: block.timestamp + 1 hours,
                preExecutionHook: IPreExecutionHook(address(dcaRegistry)),
                preExecutionHookData: abi.encode(validationData)
            }),
            input: InputToken({token: ERC20(address(tokenIn)), amount: 500e18, maxAmount: 500e18}),
            outputs: new OutputToken[](1),
            sig: "",
            hash: keccak256("test order hash"),
            auctionResolver: address(resolver)
        });
        order.outputs[0] = OutputToken({token: address(tokenOut), amount: 450e18, recipient: address(this)});

        // Should revert with invalid params
        vm.prank(address(reactor));
        vm.expectRevert(DCARegistry.InvalidDCAParams.selector);
        dcaRegistry.preExecutionHook(filler, order);
    }

    function test_rejectExpiredIntent() public {
        // Create DCA intent with past deadline
        IDCARegistry.DCAIntent memory intent =
            createPublicDCAIntent(address(tokenIn), address(tokenOut), cosigner, keccak256("private params"));
        intent.deadline = block.timestamp - 1; // Expired

        // Create cosigner data
        IDCARegistry.DCAOrderCosignerData memory cosignerData =
            createBasicCosignerData(swapper, 500e18, 450e18, keccak256("order nonce"));

        // Create validation data
        IDCARegistry.DCAValidationData memory validationData =
            createSignedDCAValidationData(intent, cosignerData, SWAPPER_PRIVATE_KEY, COSIGNER_PRIVATE_KEY, dcaRegistry);

        // Create order
        ResolvedOrderV2 memory order = ResolvedOrderV2({
            info: OrderInfoV2({
                reactor: reactor,
                swapper: address(dcaRegistry),
                nonce: 1,
                deadline: block.timestamp + 1 hours,
                preExecutionHook: IPreExecutionHook(address(dcaRegistry)),
                preExecutionHookData: abi.encode(validationData)
            }),
            input: InputToken({token: ERC20(address(tokenIn)), amount: 500e18, maxAmount: 500e18}),
            outputs: new OutputToken[](1),
            sig: "",
            hash: keccak256("test order hash"),
            auctionResolver: address(resolver)
        });
        order.outputs[0] = OutputToken({token: address(tokenOut), amount: 450e18, recipient: address(this)});

        // Should revert with intent expired
        vm.prank(address(reactor));
        vm.expectRevert(DCARegistry.IntentExpired.selector);
        dcaRegistry.preExecutionHook(filler, order);
    }

    function test_rejectUsedOrderNonce() public {
        // Create DCA intent
        IDCARegistry.DCAIntent memory intent =
            createPublicDCAIntent(address(tokenIn), address(tokenOut), cosigner, keccak256("private params"));

        bytes32 orderNonce = keccak256("order nonce");

        // Create first cosigner data
        IDCARegistry.DCAOrderCosignerData memory cosignerData1 =
            createBasicCosignerData(swapper, 500e18, 450e18, orderNonce);

        // Create validation data
        IDCARegistry.DCAValidationData memory validationData1 =
            createSignedDCAValidationData(intent, cosignerData1, SWAPPER_PRIVATE_KEY, COSIGNER_PRIVATE_KEY, dcaRegistry);

        // Create first order
        ResolvedOrderV2 memory order1 = ResolvedOrderV2({
            info: OrderInfoV2({
                reactor: reactor,
                swapper: address(dcaRegistry),
                nonce: 1,
                deadline: block.timestamp + 1 hours,
                preExecutionHook: IPreExecutionHook(address(dcaRegistry)),
                preExecutionHookData: abi.encode(validationData1)
            }),
            input: InputToken({token: ERC20(address(tokenIn)), amount: 500e18, maxAmount: 500e18}),
            outputs: new OutputToken[](1),
            sig: "",
            hash: keccak256("test order hash 1"),
            auctionResolver: address(resolver)
        });
        order1.outputs[0] = OutputToken({token: address(tokenOut), amount: 450e18, recipient: address(this)});

        // Approve and execute first order
        vm.prank(swapper);
        tokenIn.approve(address(dcaRegistry), 1000e18);

        vm.prank(address(reactor));
        dcaRegistry.preExecutionHook(filler, order1);

        // Create second order with same order nonce
        IDCARegistry.DCAOrderCosignerData memory cosignerData2 = createBasicCosignerData(
            swapper,
            500e18,
            450e18,
            orderNonce // Same nonce
        );

        IDCARegistry.DCAValidationData memory validationData2 =
            createSignedDCAValidationData(intent, cosignerData2, SWAPPER_PRIVATE_KEY, COSIGNER_PRIVATE_KEY, dcaRegistry);

        ResolvedOrderV2 memory order2 = ResolvedOrderV2({
            info: OrderInfoV2({
                reactor: reactor,
                swapper: address(dcaRegistry),
                nonce: 2,
                deadline: block.timestamp + 1 hours,
                preExecutionHook: IPreExecutionHook(address(dcaRegistry)),
                preExecutionHookData: abi.encode(validationData2)
            }),
            input: InputToken({token: ERC20(address(tokenIn)), amount: 500e18, maxAmount: 500e18}),
            outputs: new OutputToken[](1),
            sig: "",
            hash: keccak256("test order hash 2"),
            auctionResolver: address(resolver)
        });
        order2.outputs[0] = OutputToken({token: address(tokenOut), amount: 450e18, recipient: address(this)});

        // Should revert with order nonce already used
        vm.prank(address(reactor));
        vm.expectRevert(DCARegistry.OrderNonceAlreadyUsed.selector);
        dcaRegistry.preExecutionHook(filler, order2);
    }

    function test_multipleActiveOrders() public {
        // Test that multiple orders can be active simultaneously
        vm.prank(swapper);
        tokenIn.approve(address(dcaRegistry), 2000e18);

        // Create first order
        bytes32 hash1 = _createAndExecuteOrder(1, keccak256("nonce1"));

        // Create second order with different nonce
        bytes32 hash2 = _createAndExecuteOrder(2, keccak256("nonce2"));

        // Both should be active
        assertEq(dcaRegistry.isValidSignature(hash1, ""), MAGICVALUE, "First order should be active");
        assertEq(dcaRegistry.isValidSignature(hash2, ""), MAGICVALUE, "Second order should be active");

        // Mark first as complete
        dcaRegistry.markOrderComplete(hash1);

        // First should be inactive, second still active
        assertEq(dcaRegistry.isValidSignature(hash1, ""), bytes4(0), "First order should be inactive");
        assertEq(dcaRegistry.isValidSignature(hash2, ""), MAGICVALUE, "Second order should still be active");
    }

    // ===== FUZZ TESTS =====

    function testFuzz_EIP1271_randomHashes(bytes32 randomHash) public {
        // Random hashes should always return 0 (invalid)
        bytes4 result = dcaRegistry.isValidSignature(randomHash, "");
        assertEq(result, bytes4(0), "Random hash should be invalid");
    }

    function testFuzz_preExecutionHook_differentAmounts(uint256 inputAmount) public {
        // Bound input amount to reasonable range
        inputAmount = bound(inputAmount, 100e18, 1000e18);

        // Create DCA intent
        IDCARegistry.DCAIntent memory intent =
            createPublicDCAIntent(address(tokenIn), address(tokenOut), cosigner, keccak256("private params"));

        // Create cosigner data
        IDCARegistry.DCAOrderCosignerData memory cosignerData = createBasicCosignerData(
            swapper,
            inputAmount,
            inputAmount * 90 / 100, // 10% slippage
            keccak256("order nonce")
        );

        // Create validation data
        IDCARegistry.DCAValidationData memory validationData =
            createSignedDCAValidationData(intent, cosignerData, SWAPPER_PRIVATE_KEY, COSIGNER_PRIVATE_KEY, dcaRegistry);

        // Create order
        ResolvedOrderV2 memory order = ResolvedOrderV2({
            info: OrderInfoV2({
                reactor: reactor,
                swapper: address(dcaRegistry),
                nonce: 1,
                deadline: block.timestamp + 1 hours,
                preExecutionHook: IPreExecutionHook(address(dcaRegistry)),
                preExecutionHookData: abi.encode(validationData)
            }),
            input: InputToken({token: ERC20(address(tokenIn)), amount: inputAmount, maxAmount: inputAmount}),
            outputs: new OutputToken[](1),
            sig: "",
            hash: keccak256(abi.encode(inputAmount)),
            auctionResolver: address(resolver)
        });
        order.outputs[0] =
            OutputToken({token: address(tokenOut), amount: inputAmount * 90 / 100, recipient: address(this)});

        // Approve and execute
        vm.prank(swapper);
        tokenIn.approve(address(dcaRegistry), inputAmount);

        vm.prank(address(reactor));
        dcaRegistry.preExecutionHook(filler, order);

        // Verify tokens were transferred
        assertEq(tokenIn.balanceOf(address(dcaRegistry)), inputAmount, "Registry should have tokens");
        assertEq(dcaRegistry.isValidSignature(order.hash, ""), MAGICVALUE, "Order should be active");
    }

    // ===== HELPER FUNCTIONS =====

    function _createAndExecuteOrder(uint256 orderNumber, bytes32 orderNonce) internal returns (bytes32 orderHash) {
        // Create DCA intent (same intent can be used for multiple orders)
        IDCARegistry.DCAIntent memory intent = createPublicDCAIntent(
            address(tokenIn), address(tokenOut), cosigner, keccak256(abi.encode("private params", orderNumber))
        );

        // Create cosigner data
        IDCARegistry.DCAOrderCosignerData memory cosignerData =
            createBasicCosignerData(swapper, 500e18, 450e18, orderNonce);

        // Create validation data
        IDCARegistry.DCAValidationData memory validationData =
            createSignedDCAValidationData(intent, cosignerData, SWAPPER_PRIVATE_KEY, COSIGNER_PRIVATE_KEY, dcaRegistry);

        orderHash = keccak256(abi.encode(orderNumber, orderNonce));

        // Create order
        ResolvedOrderV2 memory order = ResolvedOrderV2({
            info: OrderInfoV2({
                reactor: reactor,
                swapper: address(dcaRegistry),
                nonce: orderNumber,
                deadline: block.timestamp + 1 hours,
                preExecutionHook: IPreExecutionHook(address(dcaRegistry)),
                preExecutionHookData: abi.encode(validationData)
            }),
            input: InputToken({token: ERC20(address(tokenIn)), amount: 500e18, maxAmount: 500e18}),
            outputs: new OutputToken[](1),
            sig: "",
            hash: orderHash,
            auctionResolver: address(resolver)
        });
        order.outputs[0] = OutputToken({token: address(tokenOut), amount: 450e18, recipient: address(this)});

        // Execute
        vm.prank(address(reactor));
        dcaRegistry.preExecutionHook(filler, order);
    }
}

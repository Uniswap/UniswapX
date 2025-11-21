// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "../../../util/DeployPermit2.sol";
import {DCAHookHarness} from "./DCAHookHarness.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";
import {PermitData} from "../../../../src/v4/hooks/dca/DCAStructs.sol";
import {ResolvedOrder, OrderInfo, InputToken, OutputToken} from "../../../../src/v4/base/ReactorStructs.sol";
import {IPreExecutionHook, IPostExecutionHook} from "../../../../src/v4/interfaces/IHook.sol";
import {IAuctionResolver} from "../../../../src/v4/interfaces/IAuctionResolver.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {MockERC20} from "../../../util/mock/MockERC20.sol";

contract DCAHook_transferInputTokensTest is Test, DeployPermit2 {
    DCAHookHarness hook;
    IPermit2 permit2;
    address constant REACTOR_ADDRESS = address(0x2345);
    IReactor constant REACTOR = IReactor(REACTOR_ADDRESS);

    MockERC20 inputToken;
    MockERC20 outputToken;

    address SWAPPER;
    address constant FILLER = address(0x5678);
    address constant RECIPIENT = address(0x9ABC);

    uint256 constant SWAPPER_PRIVATE_KEY = 0x12345678;
    uint256 constant AMOUNT = 1000e18;
    uint256 constant NONCE = 42;
    uint256 constant DEADLINE = 1000000000000;

    bytes32 DOMAIN_SEPARATOR;

    // EIP-712 typehashes for AllowanceTransfer
    bytes32 constant _PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");
    bytes32 constant _PERMIT_SINGLE_TYPEHASH = keccak256(
        "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
    );

    function setUp() public {
        permit2 = IPermit2(deployPermit2());
        hook = new DCAHookHarness(permit2, REACTOR);
        DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

        // Derive swapper address from private key
        SWAPPER = vm.addr(SWAPPER_PRIVATE_KEY);

        // Deploy mock tokens
        inputToken = new MockERC20("Input Token", "INPUT", 18);
        outputToken = new MockERC20("Output Token", "OUTPUT", 18);

        // Fund the swapper
        inputToken.mint(SWAPPER, AMOUNT * 10);

        // Approve permit2 from swapper for max amount (required for permit2 to work)
        vm.prank(SWAPPER);
        inputToken.approve(address(permit2), type(uint256).max);
    }

    function _createResolvedOrder(address swapper, address token, uint256 amount)
        internal
        view
        returns (ResolvedOrder memory)
    {
        InputToken memory input = InputToken({token: ERC20(token), amount: amount, maxAmount: amount});

        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0] = OutputToken({token: address(outputToken), amount: amount, recipient: RECIPIENT});

        return ResolvedOrder({
            info: OrderInfo({
                reactor: REACTOR,
                swapper: swapper,
                nonce: NONCE,
                deadline: block.timestamp + 1000,
                preExecutionHook: IPreExecutionHook(address(hook)),
                preExecutionHookData: "",
                postExecutionHook: IPostExecutionHook(address(0)),
                postExecutionHookData: "",
                auctionResolver: IAuctionResolver(address(0))
            }),
            input: input,
            outputs: outputs,
            sig: "",
            hash: bytes32(0),
            auctionResolver: address(0),
            witnessTypeString: ""
        });
    }

    function _createPermitData(bool hasPermit) internal view returns (PermitData memory) {
        if (!hasPermit) {
            return PermitData({
                hasPermit: false,
                permitSingle: IAllowanceTransfer.PermitSingle({
                    details: IAllowanceTransfer.PermitDetails({token: address(0), amount: 0, expiration: 0, nonce: 0}),
                    spender: address(0),
                    sigDeadline: 0
                }),
                signature: ""
            });
        }

        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(inputToken),
                amount: uint160(AMOUNT),
                expiration: uint48(block.timestamp + 1000),
                nonce: uint48(0) // Use current nonce from permit2
            }),
            spender: address(hook),
            sigDeadline: block.timestamp + 1000
        });

        return
            PermitData({hasPermit: true, permitSingle: permitSingle, signature: _generatePermitSignature(permitSingle)});
    }

    function _generatePermitSignature(IAllowanceTransfer.PermitSingle memory permit)
        internal
        view
        returns (bytes memory)
    {
        // Generate proper EIP-712 signature
        bytes32 permitHash = keccak256(abi.encode(_PERMIT_DETAILS_TYPEHASH, permit.details));

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(_PERMIT_SINGLE_TYPEHASH, permitHash, permit.spender, permit.sigDeadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SWAPPER_PRIVATE_KEY, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    // ============ Tests with existing allowance ============

    function test_transferInputTokens_existingAllowance_success() public {
        // Setup: Swapper sets allowance to hook via Permit2
        vm.startPrank(SWAPPER);
        permit2.approve(address(inputToken), address(hook), uint160(AMOUNT), uint48(block.timestamp + 1000));
        vm.stopPrank();

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), AMOUNT);
        PermitData memory permitData = _createPermitData(false);

        uint256 swapperBalanceBefore = inputToken.balanceOf(SWAPPER);
        uint256 fillerBalanceBefore = inputToken.balanceOf(FILLER);

        // Execute transfer
        hook.transferInputTokens(order, FILLER, permitData);

        // Verify balances
        assertEq(inputToken.balanceOf(SWAPPER), swapperBalanceBefore - AMOUNT);
        assertEq(inputToken.balanceOf(FILLER), fillerBalanceBefore + AMOUNT);
    }

    function test_transferInputTokens_existingAllowance_insufficientAllowance() public {
        // Setup: Swapper sets insufficient allowance
        vm.startPrank(SWAPPER);
        permit2.approve(address(inputToken), address(hook), uint160(AMOUNT - 1), uint48(block.timestamp + 1000));
        vm.stopPrank();

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), AMOUNT);
        PermitData memory permitData = _createPermitData(false);

        // Should revert due to insufficient allowance
        vm.expectRevert();
        hook.transferInputTokens(order, FILLER, permitData);
    }

    function test_transferInputTokens_existingAllowance_expiredAllowance() public {
        // Setup: Swapper sets allowance that's expired
        vm.startPrank(SWAPPER);
        permit2.approve(address(inputToken), address(hook), uint160(AMOUNT), uint48(block.timestamp - 1));
        vm.stopPrank();

        // Move time forward
        vm.warp(block.timestamp + 100);

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), AMOUNT);
        PermitData memory permitData = _createPermitData(false);

        // Should revert due to expired allowance
        vm.expectRevert();
        hook.transferInputTokens(order, FILLER, permitData);
    }

    function test_transferInputTokens_existingAllowance_zeroAmount() public {
        vm.startPrank(SWAPPER);
        permit2.approve(address(inputToken), address(hook), uint160(AMOUNT), uint48(block.timestamp + 1000));
        vm.stopPrank();

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), 0);
        PermitData memory permitData = _createPermitData(false);

        uint256 swapperBalanceBefore = inputToken.balanceOf(SWAPPER);
        uint256 fillerBalanceBefore = inputToken.balanceOf(FILLER);

        // Transfer zero amount should succeed
        hook.transferInputTokens(order, FILLER, permitData);

        // Verify no balance changes
        assertEq(inputToken.balanceOf(SWAPPER), swapperBalanceBefore);
        assertEq(inputToken.balanceOf(FILLER), fillerBalanceBefore);
    }

    // ============ Tests with permit signature ============

    function test_transferInputTokens_withPermit_success() public {
        // Get the current nonce for the swapper
        (,, uint48 currentNonce) = permit2.allowance(SWAPPER, address(inputToken), address(hook));

        // Create permit with proper signature
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(inputToken),
                amount: uint160(AMOUNT),
                expiration: uint48(block.timestamp + 1000),
                nonce: currentNonce
            }),
            spender: address(hook),
            sigDeadline: block.timestamp + 1000
        });

        bytes memory signature = _generatePermitSignature(permitSingle);

        PermitData memory permitData = PermitData({hasPermit: true, permitSingle: permitSingle, signature: signature});

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), AMOUNT);

        uint256 swapperBalanceBefore = inputToken.balanceOf(SWAPPER);
        uint256 fillerBalanceBefore = inputToken.balanceOf(FILLER);

        // Execute transfer with permit - this should call permit2.permit and then transferFrom
        hook.transferInputTokens(order, FILLER, permitData);

        // Verify balances changed correctly
        assertEq(inputToken.balanceOf(SWAPPER), swapperBalanceBefore - AMOUNT);
        assertEq(inputToken.balanceOf(FILLER), fillerBalanceBefore + AMOUNT);

        // Verify the nonce was incremented
        (,, uint48 newNonce) = permit2.allowance(SWAPPER, address(inputToken), address(hook));
        assertEq(newNonce, currentNonce + 1);
    }

    function test_transferInputTokens_withPermit_invalidSignature() public {
        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), AMOUNT);

        // Create permit with invalid signature
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(inputToken),
                amount: uint160(AMOUNT),
                expiration: uint48(block.timestamp + 1000),
                nonce: uint48(0)
            }),
            spender: address(hook),
            sigDeadline: block.timestamp + 1000
        });

        // Use invalid signature (all zeros)
        PermitData memory permitData = PermitData({
            hasPermit: true, permitSingle: permitSingle, signature: abi.encodePacked(bytes32(0), bytes32(0), uint8(0))
        });

        // Should revert due to invalid permit signature
        vm.expectRevert();
        hook.transferInputTokens(order, FILLER, permitData);
    }

    function test_transferInputTokens_withPermit_expiredDeadline() public {
        // Create permit with expired deadline
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(inputToken),
                amount: uint160(AMOUNT),
                expiration: uint48(block.timestamp + 1000),
                nonce: uint48(0)
            }),
            spender: address(hook),
            sigDeadline: block.timestamp - 1 // Expired deadline
        });

        bytes memory signature = _generatePermitSignature(permitSingle);

        PermitData memory permitData = PermitData({hasPermit: true, permitSingle: permitSingle, signature: signature});

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), AMOUNT);

        // Should revert due to expired signature deadline
        vm.expectRevert();
        hook.transferInputTokens(order, FILLER, permitData);
    }

    function test_transferInputTokens_withPermit_wrongNonce() public {
        // Create permit with wrong nonce
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(inputToken),
                amount: uint160(AMOUNT),
                expiration: uint48(block.timestamp + 1000),
                nonce: uint48(999) // Wrong nonce
            }),
            spender: address(hook),
            sigDeadline: block.timestamp + 1000
        });

        bytes memory signature = _generatePermitSignature(permitSingle);

        PermitData memory permitData = PermitData({hasPermit: true, permitSingle: permitSingle, signature: signature});

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), AMOUNT);

        // Should revert due to invalid nonce
        vm.expectRevert();
        hook.transferInputTokens(order, FILLER, permitData);
    }

    // ============ Edge cases ============

    function test_transferInputTokens_differentRecipient() public {
        address customRecipient = address(0xDEAD);

        vm.startPrank(SWAPPER);
        permit2.approve(address(inputToken), address(hook), uint160(AMOUNT), uint48(block.timestamp + 1000));
        vm.stopPrank();

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), AMOUNT);
        PermitData memory permitData = _createPermitData(false);

        uint256 recipientBalanceBefore = inputToken.balanceOf(customRecipient);

        // Transfer to custom recipient
        hook.transferInputTokens(order, customRecipient, permitData);

        // Verify transfer went to correct recipient
        assertEq(inputToken.balanceOf(customRecipient), recipientBalanceBefore + AMOUNT);
    }

    function test_transferInputTokens_maxUint160Amount() public {
        uint256 maxAmount = type(uint160).max;

        // Fund swapper with max amount
        inputToken.mint(SWAPPER, maxAmount);

        vm.startPrank(SWAPPER);
        permit2.approve(address(inputToken), address(hook), uint160(maxAmount), uint48(block.timestamp + 1000));
        vm.stopPrank();

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), maxAmount);
        PermitData memory permitData = _createPermitData(false);

        uint256 swapperBalanceBefore = inputToken.balanceOf(SWAPPER);
        uint256 fillerBalanceBefore = inputToken.balanceOf(FILLER);

        // Execute transfer with max amount
        hook.transferInputTokens(order, FILLER, permitData);

        // Verify balances
        assertEq(inputToken.balanceOf(SWAPPER), swapperBalanceBefore - maxAmount);
        assertEq(inputToken.balanceOf(FILLER), fillerBalanceBefore + maxAmount);
    }

    // ============ Fuzz tests ============

    function testFuzz_transferInputTokens_variousAmounts(uint160 amount) public {
        vm.assume(amount > 0 && amount <= AMOUNT);

        vm.startPrank(SWAPPER);
        permit2.approve(address(inputToken), address(hook), amount, uint48(block.timestamp + 1000));
        vm.stopPrank();

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), amount);
        PermitData memory permitData = _createPermitData(false);

        uint256 swapperBalanceBefore = inputToken.balanceOf(SWAPPER);
        uint256 fillerBalanceBefore = inputToken.balanceOf(FILLER);

        // Execute transfer
        hook.transferInputTokens(order, FILLER, permitData);

        // Verify balances
        assertEq(inputToken.balanceOf(SWAPPER), swapperBalanceBefore - amount);
        assertEq(inputToken.balanceOf(FILLER), fillerBalanceBefore + amount);
    }

    function testFuzz_transferInputTokens_variousRecipients(address recipient) public {
        vm.assume(recipient != address(0) && recipient != SWAPPER);

        vm.startPrank(SWAPPER);
        permit2.approve(address(inputToken), address(hook), uint160(AMOUNT), uint48(block.timestamp + 1000));
        vm.stopPrank();

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, address(inputToken), AMOUNT);
        PermitData memory permitData = _createPermitData(false);

        uint256 recipientBalanceBefore = inputToken.balanceOf(recipient);

        // Execute transfer
        hook.transferInputTokens(order, recipient, permitData);

        // Verify transfer went to correct recipient
        assertEq(inputToken.balanceOf(recipient), recipientBalanceBefore + AMOUNT);
    }
}

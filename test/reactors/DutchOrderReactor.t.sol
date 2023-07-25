// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    DutchOrderReactor,
    DutchOrder,
    ResolvedOrder,
    DutchOutput,
    DutchInput,
    BaseReactor
} from "../../src/reactors/DutchOrderReactor.sol";
import {OrderInfo, InputToken, OutputToken, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {DutchDecayLib} from "../../src/lib/DutchDecayLib.sol";
import {CurrencyLibrary} from "../../src/lib/CurrencyLibrary.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockDutchOrderReactor} from "../util/mock/MockDutchOrderReactor.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchOrder, DutchOrderLib} from "../../src/lib/DutchOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockFillContractWithOutputOverride} from "../util/mock/MockFillContractWithOutputOverride.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {BaseReactorTest} from "../base/BaseReactor.t.sol";

// This suite of tests test validation and resolves.
contract DutchOrderReactorValidationTest is Test, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;

    address constant PROTOCOL_FEE_OWNER = address(1);

    MockDutchOrderReactor reactor;
    IPermit2 permit2;

    function setUp() public {
        permit2 = IPermit2(deployPermit2());
        reactor = new MockDutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
    }

    // 1000 - (1000-900) * (1659087340-1659029740) / (1659130540-1659029740) = 943
    function testResolveEndTimeAfterNow() public {
        vm.warp(1659087340);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs[0].amount, 943);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(address(resolvedOrder.input.token), address(0));
    }

    // Test multiple dutch outputs get resolved correctly. Use same time points as
    // testResolveEndTimeAfterNow().
    function testResolveMultipleDutchOutputs() public {
        vm.warp(1659087340);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](3);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        dutchOutputs[1] = DutchOutput(address(0), 10000, 9000, address(0));
        dutchOutputs[2] = DutchOutput(address(0), 2000, 1000, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs.length, 3);
        assertEq(resolvedOrder.outputs[0].amount, 943);
        assertEq(resolvedOrder.outputs[1].amount, 9429);
        assertEq(resolvedOrder.outputs[2].amount, 1429);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(address(resolvedOrder.input.token), address(0));
    }

    // Test that when decayStartTime = now, that the output = startAmount
    function testResolveStartTimeEqualsNow() public {
        vm.warp(1659029740);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(address(resolvedOrder.input.token), address(0));
    }

    // startAmount is expected to always be greater than endAmount
    // otherwise the order decays out of favor for the swapper
    function testStartAmountLessThanEndAmount() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 900, 1000, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(block.timestamp + 100),
            block.timestamp,
            block.timestamp + 100,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        vm.expectRevert(DutchDecayLib.IncorrectAmounts.selector);
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    // At time 1659030747, output will still be 1000. One second later at 1659030748,
    // the first decay will occur and the output will be 999.
    function testResolveFirstDecay() public {
        vm.warp(1659030747);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs[0].amount, 1000);

        vm.warp(1659030748);
        resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs[0].amount, 999);
    }

    function testValidateDutchEndTimeBeforeStart() public {
        vm.expectRevert(DutchDecayLib.EndTimeBeforeStartTime.selector);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659130541,
            1659130540,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testValidateDutchEndTimeAfterStart() public view {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659120540,
            1659130540,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testValidateEndTimeAfterDeadline() public {
        vm.expectRevert(DutchOrderReactor.DeadlineBeforeEndTime.selector);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(100),
            50,
            101,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testOutputDecaysCorrectlyWhenNowLtEndtimeLtDeadline() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1000),
            50,
            100,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        vm.warp(75);
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.outputs[0].amount, 950);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(address(resolvedOrder.input.token), address(0));
    }

    function testOutputDecaysCorrectlyWhenEndtimeLtNowLtDeadline() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1000),
            50,
            100,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        vm.warp(200);
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.outputs[0].amount, 900);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(address(resolvedOrder.input.token), address(0));
    }

    function testOutputDecaysCorrectlyWhenEndtimeEqNowLtDeadline() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1000),
            50,
            100,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        vm.warp(100);
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.outputs[0].amount, 900);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(address(resolvedOrder.input.token), address(0));
    }

    function testInputDecaysCorrectlyWhenNowLtEndtimeLtDeadline() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1000, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1000),
            50,
            100,
            DutchInput(MockERC20(address(0)), 800, 1000),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        vm.warp(75);
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 900);
        assertEq(address(resolvedOrder.input.token), address(0));
    }

    function testInputDecaysCorrectlyWhenEndtimeLtNowLtDeadline() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1000, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1000),
            50,
            100,
            DutchInput(MockERC20(address(0)), 800, 1000),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        vm.warp(300);
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1000);
        assertEq(address(resolvedOrder.input.token), address(0));
    }

    function testDecayNeverOutOfBounds(
        uint256 decayStartTime,
        uint256 startAmount,
        uint256 decayEndTime,
        uint256 endAmount
    ) public {
        vm.assume(decayStartTime < decayEndTime);
        vm.assume(startAmount > endAmount);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), startAmount, endAmount, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(decayEndTime),
            decayStartTime,
            decayEndTime,
            DutchInput(MockERC20(address(0)), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertLe(resolvedOrder.outputs[0].amount, startAmount);
        assertGe(resolvedOrder.outputs[0].amount, endAmount);
    }

    // The input decays, which means the outputs must not decay. In this test, the
    // 2nd output decays, so revert with error InputAndOutputDecay().
    function testBothInputAndOutputDecay() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1000, address(0));
        dutchOutputs[1] = DutchOutput(address(0), 1000, 900, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659130500,
            1659130540,
            DutchInput(MockERC20(address(0)), 100, 110),
            dutchOutputs
        );
        vm.expectRevert(DutchOrderReactor.InputAndOutputDecay.selector);
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testInputDecayIncorrectAmounts() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1000, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659130500,
            1659130540,
            DutchInput(MockERC20(address(0)), 110, 100),
            dutchOutputs
        );
        vm.expectRevert(DutchDecayLib.IncorrectAmounts.selector);
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testOutputDecayIncorrectAmounts() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1100, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659130500,
            1659130540,
            DutchInput(MockERC20(address(0)), 100, 100),
            dutchOutputs
        );
        vm.expectRevert(DutchDecayLib.IncorrectAmounts.selector);
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testInputDecayStartTimeAfterNow() public {
        uint256 mockNow = 1659050541;
        vm.warp(mockNow);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1000, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            mockNow + 1,
            1659130540,
            DutchInput(MockERC20(address(0)), 2000, 2500),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.input.amount, 2000);
    }

    // 2000+(2500-2000)*(20801/70901) = 2146
    function testInputDecayNowBetweenStartAndEnd() public {
        uint256 mockNow = 1659050541;
        vm.warp(mockNow);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1000, address(0));
        DutchOrder memory dlo = DutchOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659100641),
            1659029740,
            1659100641,
            DutchInput(MockERC20(address(0)), 2000, 2500),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.input.amount, 2146);
    }
}

// This suite of tests test execution with a mock fill contract.
contract DutchOrderReactorExecuteTest is PermitSignature, DeployPermit2, BaseReactorTest {
    using OrderInfoBuilder for OrderInfo;
    using DutchOrderLib for DutchOrder;

    function name() public pure override returns (string memory) {
        return "DutchOrder";
    }

    function createReactor() public override returns (BaseReactor) {
        return new DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
    }

    /// @dev Create and return a basic single Dutch limit order along with its signature, orderHash, and orderInfo
    /// TODO: Support creating a single dutch order with multiple outputs
    function createAndSignOrder(ResolvedOrder memory request)
        public
        view
        override
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        DutchOutput[] memory outputs = new DutchOutput[](request.outputs.length);
        for (uint256 i = 0; i < request.outputs.length; i++) {
            OutputToken memory output = request.outputs[i];
            outputs[i] = DutchOutput({
                token: output.token,
                startAmount: output.amount,
                endAmount: output.amount,
                recipient: output.recipient
            });
        }

        DutchOrder memory order = DutchOrder({
            info: request.info,
            decayStartTime: block.timestamp,
            decayEndTime: request.info.deadline,
            input: DutchInput(request.input.token, request.input.amount, request.input.amount),
            outputs: outputs
        });
        orderHash = order.hash();
        return (SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)), orderHash);
    }

    // Execute 3 dutch orders. Have the 3rd one signed by a different swapper.
    // Order 1: Input = 1, outputs = [2, 1]
    // Order 2: Input = 2, outputs = [3]
    // Order 3: Input = 3, outputs = [3,4,5]
    function testExecuteBatchMultipleOutputs() public {
        uint256 swapperPrivateKey2 = 0x12341235;
        address swapper2 = vm.addr(swapperPrivateKey2);

        tokenIn.mint(address(swapper), 3 ether);
        tokenIn.mint(address(swapper2), 3 ether);
        tokenOut.mint(address(fillContract), 18 ether);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        tokenIn.forceApprove(swapper2, address(permit2), type(uint256).max);

        // Build the 3 orders
        DutchOrder[] memory orders = new DutchOrder[](3);

        uint256[] memory startAmounts0 = new uint256[](2);
        startAmounts0[0] = 2 ether;
        startAmounts0[1] = 10 ** 18;
        uint256[] memory endAmounts0 = new uint256[](2);
        endAmounts0[0] = startAmounts0[0];
        endAmounts0[1] = startAmounts0[1];
        orders[0] = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, 10 ** 18, 10 ** 18),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts0, endAmounts0, swapper)
        });

        orders[1] = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, 2 ether, 2 ether),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), 3 ether, 3 ether, swapper)
        });

        uint256[] memory startAmounts2 = new uint256[](3);
        startAmounts2[0] = 3 ether;
        startAmounts2[1] = 4 ether;
        startAmounts2[2] = 5 ether;
        uint256[] memory endAmounts2 = new uint256[](3);
        endAmounts2[0] = startAmounts2[0];
        endAmounts2[1] = startAmounts2[1];
        endAmounts2[2] = startAmounts2[2];
        orders[2] = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100)
                .withNonce(2),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, 3 ether, 3 ether),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts2, endAmounts2, swapper2)
        });
        SignedOrder[] memory signedOrders = generateSignedOrders(orders);
        // different swapper
        signedOrders[2].sig = signOrder(swapperPrivateKey2, address(permit2), orders[2]);

        vm.expectEmit(false, false, false, true);
        emit Fill(orders[0].hash(), address(this), swapper, orders[0].info.nonce);
        vm.expectEmit(false, false, false, true);
        emit Fill(orders[1].hash(), address(this), swapper, orders[1].info.nonce);
        vm.expectEmit(false, false, false, true);
        emit Fill(orders[2].hash(), address(this), swapper2, orders[2].info.nonce);
        fillContract.executeBatch(signedOrders);
        assertEq(tokenOut.balanceOf(swapper), 6 ether);
        assertEq(tokenOut.balanceOf(swapper2), 12 ether);
        assertEq(tokenIn.balanceOf(address(fillContract)), 6 ether);
    }

    // Execute 2 dutch orders. The 1st one has input = 1, outputs = [2]. The 2nd one
    // has input = 2, outputs = [4]. However, only mint 5 output to fillContract, so there
    // will be an overflow error when reactor tries to transfer out 4 output out of the
    // fillContract for the second order.
    function testExecuteBatchInsufficientOutput() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 3);
        tokenOut.mint(address(fillContract), 5 ether);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        DutchOrder[] memory orders = new DutchOrder[](2);
        orders[0] = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });
        orders[1] = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount * 2, inputAmount * 2),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, swapper)
        });

        vm.expectRevert();
        fillContract.executeBatch(generateSignedOrders(orders));
    }

    // Execute 2 dutch orders, but executor does not send enough output tokens to the recipient
    // should fail with InsufficientOutput error from balance checks
    function testExecuteBatchInsufficientOutputSent() public {
        MockFillContractWithOutputOverride fill = new MockFillContractWithOutputOverride(address(reactor));
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 3);
        tokenOut.mint(address(fill), 5 ether);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        DutchOrder[] memory orders = new DutchOrder[](2);
        orders[0] = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });
        orders[1] = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount * 2, inputAmount * 2),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, swapper)
        });

        fill.setOutputAmount(outputAmount);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        fill.executeBatch(generateSignedOrders(orders));
    }

    // Execute 2 dutch orders, but executor does not send enough output ETH to the recipient
    // should fail with InsufficientOutput error from balance checks
    function testExecuteBatchInsufficientOutputSentNative() public {
        MockFillContractWithOutputOverride fill = new MockFillContractWithOutputOverride(address(reactor));
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 2);
        vm.deal(address(fill), 2 ether);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        DutchOrder[] memory orders = new DutchOrder[](2);
        orders[0] = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, swapper)
        });
        orders[1] = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, swapper)
        });

        fill.setOutputAmount(outputAmount / 2);
        vm.expectRevert(CurrencyLibrary.NativeTransferFailed.selector);
        fill.executeBatch(generateSignedOrders(orders));
    }

    function generateSignedOrders(DutchOrder[] memory orders) private view returns (SignedOrder[] memory result) {
        result = new SignedOrder[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            bytes memory sig = signOrder(swapperPrivateKey, address(permit2), orders[i]);
            result[i] = SignedOrder(abi.encode(orders[i]), sig);
        }
    }
}

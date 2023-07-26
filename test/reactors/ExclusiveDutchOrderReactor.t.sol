// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    ExclusiveDutchOrderReactor,
    ExclusiveDutchOrder,
    ResolvedOrder,
    DutchOutput,
    DutchInput,
    BaseReactor
} from "../../src/reactors/ExclusiveDutchOrderReactor.sol";
import {OrderInfo, InputToken, SignedOrder, OutputToken} from "../../src/base/ReactorStructs.sol";
import {DutchDecayLib} from "../../src/lib/DutchDecayLib.sol";
import {CurrencyLibrary, NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {ExclusiveDutchOrderLib} from "../../src/lib/ExclusiveDutchOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockFillContractWithOutputOverride} from "../util/mock/MockFillContractWithOutputOverride.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {BaseReactorTest} from "../base/BaseReactor.t.sol";

contract ExclusiveDutchOrderReactorExecuteTest is PermitSignature, DeployPermit2, BaseReactorTest {
    using OrderInfoBuilder for OrderInfo;
    using ExclusiveDutchOrderLib for ExclusiveDutchOrder;

    function name() public pure override returns (string memory) {
        return "ExclusiveDutchOrder";
    }

    function createReactor() public override returns (BaseReactor) {
        return new ExclusiveDutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
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

        ExclusiveDutchOrder memory order = ExclusiveDutchOrder({
            info: request.info,
            decayStartTime: block.timestamp,
            decayEndTime: request.info.deadline,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
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
        ExclusiveDutchOrder[] memory orders = new ExclusiveDutchOrder[](3);

        uint256[] memory startAmounts0 = new uint256[](2);
        startAmounts0[0] = 2 ether;
        startAmounts0[1] = 10 ** 18;
        uint256[] memory endAmounts0 = new uint256[](2);
        endAmounts0[0] = startAmounts0[0];
        endAmounts0[1] = startAmounts0[1];
        orders[0] = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(tokenIn, 10 ** 18, 10 ** 18),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts0, endAmounts0, swapper)
        });

        orders[1] = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
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
        orders[2] = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100)
                .withNonce(2),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
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

        ExclusiveDutchOrder[] memory orders = new ExclusiveDutchOrder[](2);
        orders[0] = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });
        orders[1] = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(tokenIn, inputAmount * 2, inputAmount * 2),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, swapper)
        });

        vm.expectRevert("TRANSFER_FROM_FAILED");
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

        ExclusiveDutchOrder[] memory orders = new ExclusiveDutchOrder[](2);
        orders[0] = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });
        orders[1] = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(tokenIn, inputAmount * 2, inputAmount * 2),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, swapper)
        });

        fill.setOutputAmount(outputAmount);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        fillContract.executeBatch(generateSignedOrders(orders));
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

        ExclusiveDutchOrder[] memory orders = new ExclusiveDutchOrder[](2);
        orders[0] = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, swapper)
        });
        orders[1] = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, swapper)
        });

        fill.setOutputAmount(outputAmount / 2);
        vm.expectRevert(CurrencyLibrary.NativeTransferFailed.selector);
        fillContract.executeBatch(generateSignedOrders(orders));
    }

    function testExclusivitySucceeds(address exclusive, uint128 amountIn, uint128 amountOut) public {
        vm.assume(exclusive != address(0));
        tokenIn.mint(address(swapper), amountIn);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        tokenOut.mint(address(exclusive), amountOut);
        tokenOut.forceApprove(exclusive, address(reactor), type(uint256).max);

        ExclusiveDutchOrder memory order = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: exclusive,
            exclusivityOverrideBps: 300,
            input: DutchInput(tokenIn, amountIn, amountIn),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), amountOut, amountOut, swapper)
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        SignedOrder memory signedOrder = SignedOrder(abi.encode(order), sig);

        vm.expectEmit(false, false, false, true);
        emit Fill(order.hash(), address(exclusive), swapper, order.info.nonce);

        vm.prank(exclusive);
        reactor.execute(signedOrder);
        assertEq(tokenOut.balanceOf(swapper), amountOut);
        assertEq(tokenIn.balanceOf(address(exclusive)), amountIn);
    }

    function testExclusivityOverride(
        address caller,
        address exclusive,
        uint256 amountIn,
        uint128 amountOut,
        uint256 overrideAmt
    ) public {
        vm.assume(exclusive != address(0));
        vm.assume(exclusive != caller && exclusive != address(fillContract));
        vm.assume(overrideAmt > 0 && overrideAmt < 10000);
        tokenIn.mint(address(swapper), amountIn);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        tokenOut.mint(address(fillContract), uint256(amountOut) * 2);

        ExclusiveDutchOrder memory order = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: exclusive,
            exclusivityOverrideBps: overrideAmt,
            input: DutchInput(tokenIn, amountIn, amountIn),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), amountOut, amountOut, swapper)
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        SignedOrder memory signedOrder = SignedOrder(abi.encode(order), sig);

        vm.expectEmit(false, false, false, true);
        emit Fill(order.hash(), address(this), swapper, order.info.nonce);

        vm.prank(caller);
        fillContract.execute(signedOrder);
        assertEq(tokenOut.balanceOf(swapper), amountOut * (10000 + overrideAmt) / 10000);
        assertEq(tokenIn.balanceOf(address(fillContract)), amountIn);
    }

    function testExclusivityMultipleOutputs(
        address caller,
        address exclusive,
        uint256 amountIn,
        uint128[] memory amountOuts,
        uint256 overrideAmt
    ) public {
        vm.assume(exclusive != address(0));
        vm.assume(exclusive != caller);
        vm.assume(overrideAmt > 0 && overrideAmt < 10000);
        tokenIn.mint(address(swapper), amountIn);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        uint256 amountOutSum = 0;
        for (uint256 i = 0; i < amountOuts.length; i++) {
            amountOutSum += amountOuts[i] * (10000 + overrideAmt) / 10000;
        }
        tokenOut.mint(address(fillContract), uint256(amountOutSum));

        uint256[] memory amounts = new uint256[](amountOuts.length);
        for (uint256 i = 0; i < amountOuts.length; i++) {
            amounts[i] = amountOuts[i];
        }

        ExclusiveDutchOrder memory order = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: exclusive,
            exclusivityOverrideBps: overrideAmt,
            input: DutchInput(tokenIn, amountIn, amountIn),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), amounts, amounts, swapper)
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        SignedOrder memory signedOrder = SignedOrder(abi.encode(order), sig);

        vm.expectEmit(false, false, false, true);
        emit Fill(order.hash(), address(this), swapper, order.info.nonce);

        vm.prank(caller);
        fillContract.execute(signedOrder);
        assertEq(tokenOut.balanceOf(swapper), amountOutSum);
        assertEq(tokenIn.balanceOf(address(fillContract)), amountIn);
    }

    function generateSignedOrders(ExclusiveDutchOrder[] memory orders)
        private
        view
        returns (SignedOrder[] memory result)
    {
        result = new SignedOrder[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            bytes memory sig = signOrder(swapperPrivateKey, address(permit2), orders[i]);
            result[i] = SignedOrder(abi.encode(orders[i]), sig);
        }
    }
}

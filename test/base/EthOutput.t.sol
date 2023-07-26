// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {CurrencyLibrary, NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {DutchOrderReactor, DutchOrder, DutchInput, DutchOutput} from "../../src/reactors/DutchOrderReactor.sol";
import {ProtocolFees} from "../../src/base/ProtocolFees.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {DutchOrderLib} from "../../src/lib/DutchOrderLib.sol";
import {IReactorCallback} from "../../src/interfaces/IReactorCallback.sol";

// This contract will test ETH outputs using DutchOrderReactor as the reactor and MockFillContract for fillContract.
// Note that this contract only tests ETH outputs when NOT using direct filler.
contract EthOutputMockFillContractTest is Test, DeployPermit2, PermitSignature, GasSnapshot {
    using OrderInfoBuilder for OrderInfo;

    address constant PROTOCOL_FEE_OWNER = address(2);
    uint256 constant ONE = 10 ** 18;

    MockERC20 tokenIn1;
    MockERC20 tokenOut1;
    uint256 swapperPrivateKey1;
    address swapper1;
    uint256 swapperPrivateKey2;
    address swapper2;
    DutchOrderReactor reactor;
    IPermit2 permit2;
    MockFillContract fillContract;

    function setUp() public {
        tokenIn1 = new MockERC20("tokenIn1", "IN1", 18);
        tokenOut1 = new MockERC20("tokenOut1", "OUT1", 18);
        swapperPrivateKey1 = 0x12341234;
        swapper1 = vm.addr(swapperPrivateKey1);
        swapperPrivateKey2 = 0x12341235;
        swapper2 = vm.addr(swapperPrivateKey2);
        permit2 = IPermit2(deployPermit2());
        reactor = new DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
        fillContract = new MockFillContract(address(reactor));
        tokenIn1.forceApprove(swapper1, address(permit2), type(uint256).max);
        tokenIn1.forceApprove(swapper2, address(permit2), type(uint256).max);
    }

    // Fill one order (from swapper1, input = 1 tokenIn, output = 0.5 ETH (starts at 1 but decays to 0.5))
    function testEthOutput() public {
        tokenIn1.mint(address(swapper1), ONE);
        vm.deal(address(fillContract), ONE);

        vm.warp(1000);
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE, 0, swapper1)
        });
        snapStart("EthOutputTestEthOutput");
        fillContract.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), ONE);
        // There is 0.5 ETH remaining in the fillContract as output has decayed to 0.5 ETH
        assertEq(address(fillContract).balance, ONE / 2);
        assertEq(address(swapper1).balance, ONE / 2);
    }

    // Fill 3 orders
    // order 1: by swapper1, input = 1 tokenIn1, output = [2 ETH, 3 tokenOut1]
    // order 2: by swapper2, input = 2 tokenIn1, output = [3 ETH]
    // order 3: by swapper2, input = 3 tokenIn1, output = [4 tokenOut1]
    function test3OrdersWithEthAndERC20Outputs() public {
        tokenIn1.mint(address(swapper1), ONE);
        tokenIn1.mint(address(swapper2), ONE * 5);
        tokenOut1.mint(address(fillContract), ONE * 7);
        vm.deal(address(fillContract), ONE * 5);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(NATIVE, 2 * ONE, 2 * ONE, swapper1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), 3 * ONE, 3 * ONE, swapper1);
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, ONE, ONE),
            outputs: dutchOutputs
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, 3 * ONE, 3 * ONE, swapper2)
        });
        DutchOrder memory order3 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, 3 * ONE, 3 * ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), 4 * ONE, 4 * ONE, swapper2)
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](3);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, address(permit2), order2));
        signedOrders[2] = SignedOrder(abi.encode(order3), signOrder(swapperPrivateKey2, address(permit2), order3));
        snapStart("EthOutputTest3OrdersWithEthAndERC20Outputs");
        fillContract.executeBatch(signedOrders);
        snapEnd();
        assertEq(tokenOut1.balanceOf(swapper1), 3 * ONE);
        assertEq(swapper1.balance, 2 * ONE);
        assertEq(swapper2.balance, 3 * ONE);
        assertEq(tokenOut1.balanceOf(swapper2), 4 * ONE);
        assertEq(tokenIn1.balanceOf(address(fillContract)), 6 * ONE);
        assertEq(address(fillContract).balance, 0);
    }

    // Same as `test3OrdersWithEthAndERC20Outputs` but the fillContract does not have enough ETH. The reactor does
    // not have enough ETH to cover the remainder, so we will revert with `NativeTransferFailed()`.
    function test3OrdersWithEthAndERC20OutputsWithInsufficientEth() public {
        tokenIn1.mint(address(swapper1), ONE);
        tokenIn1.mint(address(swapper2), ONE * 5);
        tokenOut1.mint(address(fillContract), ONE * 7);
        // Give fillContract only 4 ETH, when it requires 5
        vm.deal(address(fillContract), ONE * 4);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(NATIVE, 2 * ONE, 2 * ONE, swapper1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), 3 * ONE, 3 * ONE, swapper1);
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, ONE, ONE),
            outputs: dutchOutputs
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, 3 * ONE, 3 * ONE, swapper2)
        });
        DutchOrder memory order3 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, 3 * ONE, 3 * ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), 4 * ONE, 4 * ONE, swapper2)
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](3);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, address(permit2), order2));
        signedOrders[2] = SignedOrder(abi.encode(order3), signOrder(swapperPrivateKey2, address(permit2), order3));
        vm.expectRevert(CurrencyLibrary.NativeTransferFailed.selector);
        fillContract.executeBatch(signedOrders);
    }

    // Same as `test3OrdersWithEthAndERC20Outputs` but the fillContract does not have enough ETH. The reactor DOES
    // have enough ETH to cover the remainder, so we will revert with `EtherSendFail()`.
    function test3OrdersWithEthAndERC20OutputsWithInsufficientEthInFillContractButEnoughInReactor() public {
        tokenIn1.mint(address(swapper1), ONE);
        tokenIn1.mint(address(swapper2), ONE * 5);
        tokenOut1.mint(address(fillContract), ONE * 7);
        // Give fillContract only 4 ETH, when it requires 5
        vm.deal(address(fillContract), ONE * 4);
        vm.deal(address(reactor), ONE * 100);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(NATIVE, 2 * ONE, 2 * ONE, swapper1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), 3 * ONE, 3 * ONE, swapper1);
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, ONE, ONE),
            outputs: dutchOutputs
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, 3 * ONE, 3 * ONE, swapper2)
        });
        DutchOrder memory order3 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, 3 * ONE, 3 * ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), 4 * ONE, 4 * ONE, swapper2)
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](3);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, address(permit2), order2));
        signedOrders[2] = SignedOrder(abi.encode(order3), signOrder(swapperPrivateKey2, address(permit2), order3));
        vm.expectRevert(CurrencyLibrary.NativeTransferFailed.selector);
        fillContract.executeBatch(signedOrders);
    }
}

// This contract will test ETH outputs using DutchOrderReactor as the reactor and direct filler.
contract EthOutputDirectFillerTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using DutchOrderLib for DutchOrder;

    address constant PROTOCOL_FEE_OWNER = address(2);
    uint256 constant ONE = 10 ** 18;

    MockERC20 tokenIn1;
    MockERC20 tokenIn2;
    MockERC20 tokenIn3;
    MockERC20 tokenOut1;
    MockERC20 tokenOut2;
    MockERC20 tokenOut3;
    uint256 swapperPrivateKey1;
    address swapper1;
    uint256 swapperPrivateKey2;
    address swapper2;
    address directFiller;
    DutchOrderReactor reactor;
    IPermit2 permit2;

    function setUp() public {
        tokenIn1 = new MockERC20("tokenIn1", "IN1", 18);
        tokenIn2 = new MockERC20("tokenIn2", "IN2", 18);
        tokenIn3 = new MockERC20("tokenIn3", "IN3", 18);
        tokenOut1 = new MockERC20("tokenOut1", "OUT1", 18);
        tokenOut2 = new MockERC20("tokenOut2", "OUT2", 18);
        tokenOut3 = new MockERC20("tokenOut3", "OUT3", 18);
        swapperPrivateKey1 = 0x12341234;
        swapper1 = vm.addr(swapperPrivateKey1);
        swapperPrivateKey2 = 0x12341235;
        swapper2 = vm.addr(swapperPrivateKey2);
        directFiller = address(888);
        permit2 = IPermit2(deployPermit2());
        reactor = new DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
        tokenIn1.forceApprove(swapper1, address(permit2), type(uint256).max);
        tokenIn1.forceApprove(swapper2, address(permit2), type(uint256).max);
        tokenIn2.forceApprove(swapper2, address(permit2), type(uint256).max);
        tokenIn3.forceApprove(swapper2, address(permit2), type(uint256).max);
        tokenOut1.forceApprove(directFiller, address(reactor), type(uint256).max);
        tokenOut2.forceApprove(directFiller, address(reactor), type(uint256).max);
        tokenOut3.forceApprove(directFiller, address(reactor), type(uint256).max);
    }

    // Fill 1 order with requested output = 2 ETH.
    function testEth1Output() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        vm.deal(directFiller, outputAmount);

        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, swapper1)
        });

        vm.prank(directFiller);
        snapStart("DirectFillerFillMacroTestEth1Output");
        reactor.execute{value: outputAmount}(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order))
        );
        snapEnd();
        assertEq(tokenIn1.balanceOf(directFiller), inputAmount);
        assertEq(swapper1.balance, outputAmount);
    }

    function testExcessETHIsReturned() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        vm.deal(directFiller, outputAmount * 2);

        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, swapper1)
        });

        vm.prank(directFiller);
        reactor.execute{value: outputAmount * 2}(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order))
        );
        // check directFiller received refund
        assertEq(directFiller.balance, outputAmount);
        assertEq(tokenIn1.balanceOf(directFiller), inputAmount);
        assertEq(swapper1.balance, outputAmount);
    }

    // The same as testEth1Output, but reverts because directFiller doesn't send enough ether
    function testEth1OutputInsufficientEthSent() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        vm.deal(directFiller, outputAmount);

        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, swapper1)
        });

        vm.prank(directFiller);
        vm.expectRevert(CurrencyLibrary.NativeTransferFailed.selector);
        reactor.execute{value: outputAmount - 1}(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order))
        );
    }

    // Fill 2 orders, both from `swapper1`, one with output = 1 ETH and another with output = 2 ETH.
    function testEth2Outputs() public {
        uint256 inputAmount = 10 ** 18;

        tokenIn1.mint(address(swapper1), inputAmount * 2);
        vm.deal(directFiller, ONE * 3);

        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE, ONE, swapper1)
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE * 2, ONE * 2, swapper1)
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey1, address(permit2), order2));

        vm.prank(directFiller);
        snapStart("DirectFillerFillMacroTestEth2Outputs");
        reactor.executeBatch{value: ONE * 3}(signedOrders);
        snapEnd();
        assertEq(tokenIn1.balanceOf(directFiller), 2 * inputAmount);
        assertEq(swapper1.balance, 3 * ONE);
    }

    // Fill 3 orders via direct filler. The same as test3OrdersWithEthAndERC20Outputs test above.
    // order 1: by swapper1, input = 1 tokenIn1, output = [2 ETH, 3 tokenOut1]
    // order 2: by swapper2, input = 2 tokenIn1, output = [3 ETH]
    // order 3: by swapper2, input = 3 tokenIn1, output = [4 tokenOut1]
    function test3OrdersWithEthAndERC20OutputsDirectFill() public {
        tokenIn1.mint(address(swapper1), ONE);
        tokenIn1.mint(address(swapper2), ONE * 5);
        tokenOut1.mint(directFiller, ONE * 7);
        vm.deal(directFiller, ONE * 5);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(NATIVE, 2 * ONE, 2 * ONE, swapper1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), 3 * ONE, 3 * ONE, swapper1);
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, ONE, ONE),
            outputs: dutchOutputs
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, 3 * ONE, 3 * ONE, swapper2)
        });
        DutchOrder memory order3 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, 3 * ONE, 3 * ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), 4 * ONE, 4 * ONE, swapper2)
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](3);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, address(permit2), order2));
        signedOrders[2] = SignedOrder(abi.encode(order3), signOrder(swapperPrivateKey2, address(permit2), order3));

        vm.prank(directFiller);
        reactor.executeBatch{value: ONE * 5}(signedOrders);
        assertEq(tokenOut1.balanceOf(swapper1), 3 * ONE);
        assertEq(swapper1.balance, 2 * ONE);
        assertEq(swapper2.balance, 3 * ONE);
        assertEq(tokenOut1.balanceOf(swapper2), 4 * ONE);
        assertEq(tokenIn1.balanceOf(directFiller), 6 * ONE);
        assertEq(directFiller.balance, 0);
    }

    // The same as testEth2Outputs, but only give directFiller 2.5 ETH which is only sufficient to fill the 1st order
    // but not the 2nd.
    function test2EthOutputOrdersButOnlyEnoughEthToFill1() public {
        uint256 inputAmount = 10 ** 18;

        tokenIn1.mint(address(swapper1), inputAmount * 2);
        vm.deal(directFiller, ONE * 5 / 2);

        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE, ONE, swapper1)
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE * 2, ONE * 2, swapper1)
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey1, address(permit2), order2));

        vm.prank(directFiller);
        vm.expectRevert(CurrencyLibrary.NativeTransferFailed.selector);
        reactor.executeBatch{value: ONE * 5 / 2}(signedOrders);
    }
}

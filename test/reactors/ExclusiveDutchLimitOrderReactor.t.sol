// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    ExclusiveDutchLimitOrderReactor,
    ExclusiveDutchLimitOrder,
    ResolvedOrder,
    DutchOutput,
    DutchInput,
    BaseReactor
} from "../../src/reactors/ExclusiveDutchLimitOrderReactor.sol";
import {OrderInfo, InputToken, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {DutchDecayLib} from "../../src/lib/DutchDecayLib.sol";
import {ExpectedBalanceLib} from "../../src/lib/ExpectedBalanceLib.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {ExclusiveDutchLimitOrderLib} from "../../src/lib/ExclusiveDutchLimitOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockFillContractWithOutputOverride} from "../util/mock/MockFillContractWithOutputOverride.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {BaseReactorTest} from "../base/BaseReactor.t.sol";

contract ExclusiveDutchLimitOrderReactorExecuteTest is PermitSignature, DeployPermit2, BaseReactorTest {
    using OrderInfoBuilder for OrderInfo;
    using ExclusiveDutchLimitOrderLib for ExclusiveDutchLimitOrder;

    address constant PROTOCOL_FEE_RECIPIENT = address(1);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    function setUp() public override {
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        permit2 = ISignatureTransfer(deployPermit2());
        createReactor();
    }

    function name() public pure override returns (string memory) {
        return "ExclusiveDutchLimitOrder";
    }

    function createReactor() public override returns (BaseReactor) {
        reactor = new ExclusiveDutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        return reactor;
    }

    /// @dev Create and return a basic single Dutch limit order along with its signature, orderHash, and orderInfo
    /// TODO: Support creating a single dutch order with multiple outputs
    function createAndSignOrder(OrderInfo memory _info, uint256 inputAmount, uint256 outputAmount)
        public
        view
        override
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        ExclusiveDutchLimitOrder memory order = ExclusiveDutchLimitOrder({
            info: _info,
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });
        orderHash = order.hash();
        return (SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)), orderHash);
    }

    /// @dev Create an return an array of basic single Dutch limit orders along with their signatures, orderHashes, and orderInfos
    function createAndSignBatchOrders(
        OrderInfo[] memory _infos,
        uint256[] memory inputAmounts,
        uint256[][] memory outputAmounts
    ) public override returns (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) {
        // Constraint should still work for inputs with multiple outputs, outputs will be [[output1, output2], [output1, output2], ...]
        assertEq(inputAmounts.length, outputAmounts.length);

        signedOrders = new SignedOrder[](inputAmounts.length);
        orderHashes = new bytes32[](inputAmounts.length);

        for (uint256 i = 0; i < inputAmounts.length; i++) {
            DutchOutput[] memory dutchOutput;
            if (outputAmounts[i].length == 1) {
                dutchOutput =
                    OutputsBuilder.singleDutch(address(tokenOut), outputAmounts[i][0], outputAmounts[i][0], maker);
            } else {
                dutchOutput = OutputsBuilder.multipleDutch(address(tokenOut), outputAmounts[i], outputAmounts[i], maker);
            }
            ExclusiveDutchLimitOrder memory order = ExclusiveDutchLimitOrder({
                info: _infos[i],
                startTime: block.timestamp,
                endTime: block.timestamp + 100,
                exclusiveFiller: address(0),
                exclusivityOverrideBps: 300,
                input: DutchInput(address(tokenIn), inputAmounts[i], inputAmounts[i]),
                outputs: dutchOutput
            });
            orderHashes[i] = order.hash();
            signedOrders[i] = SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order));
        }
        return (signedOrders, orderHashes);
    }

    // Execute 3 dutch limit orders. Have the 3rd one signed by a different maker.
    // Order 1: Input = 1, outputs = [2, 1]
    // Order 2: Input = 2, outputs = [3]
    // Order 3: Input = 3, outputs = [3,4,5]
    function testExecuteBatchMultipleOutputs() public {
        uint256 makerPrivateKey2 = 0x12341235;
        address maker2 = vm.addr(makerPrivateKey2);

        tokenIn.mint(address(maker), 3 * 10 ** 18);
        tokenIn.mint(address(maker2), 3 * 10 ** 18);
        tokenOut.mint(address(fillContract), 18 * 10 ** 18);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);
        tokenIn.forceApprove(maker2, address(permit2), type(uint256).max);

        // Build the 3 orders
        ExclusiveDutchLimitOrder[] memory orders = new ExclusiveDutchLimitOrder[](3);

        uint256[] memory startAmounts0 = new uint256[](2);
        startAmounts0[0] = 2 * 10 ** 18;
        startAmounts0[1] = 10 ** 18;
        uint256[] memory endAmounts0 = new uint256[](2);
        endAmounts0[0] = startAmounts0[0];
        endAmounts0[1] = startAmounts0[1];
        orders[0] = ExclusiveDutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(address(tokenIn), 10 ** 18, 10 ** 18),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts0, endAmounts0, maker)
        });

        orders[1] = ExclusiveDutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(address(tokenIn), 2 * 10 ** 18, 2 * 10 ** 18),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), 3 * 10 ** 18, 3 * 10 ** 18, maker)
        });

        uint256[] memory startAmounts2 = new uint256[](3);
        startAmounts2[0] = 3 * 10 ** 18;
        startAmounts2[1] = 4 * 10 ** 18;
        startAmounts2[2] = 5 * 10 ** 18;
        uint256[] memory endAmounts2 = new uint256[](3);
        endAmounts2[0] = startAmounts2[0];
        endAmounts2[1] = startAmounts2[1];
        endAmounts2[2] = startAmounts2[2];
        orders[2] = ExclusiveDutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker2).withDeadline(block.timestamp + 100).withNonce(
                2
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(address(tokenIn), 3 * 10 ** 18, 3 * 10 ** 18),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts2, endAmounts2, maker2)
        });
        SignedOrder[] memory signedOrders = generateSignedOrders(orders);
        // different maker
        signedOrders[2].sig = signOrder(makerPrivateKey2, address(permit2), orders[2]);

        vm.expectEmit(false, false, false, true);
        emit Fill(orders[0].hash(), address(this), maker, orders[0].info.nonce);
        vm.expectEmit(false, false, false, true);
        emit Fill(orders[1].hash(), address(this), maker, orders[1].info.nonce);
        vm.expectEmit(false, false, false, true);
        emit Fill(orders[2].hash(), address(this), maker2, orders[2].info.nonce);
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
        assertEq(tokenOut.balanceOf(maker), 6 * 10 ** 18);
        assertEq(tokenOut.balanceOf(maker2), 12 * 10 ** 18);
        assertEq(tokenIn.balanceOf(address(fillContract)), 6 * 10 ** 18);
    }

    // Execute 2 dutch limit orders. The 1st one has input = 1, outputs = [2]. The 2nd one
    // has input = 2, outputs = [4]. However, only mint 5 output to fillContract, so there
    // will be an overflow error when reactor tries to transfer out 4 output out of the
    // fillContract for the second order.
    function testExecuteBatchInsufficientOutput() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount * 3);
        tokenOut.mint(address(fillContract), 5 * 10 ** 18);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        ExclusiveDutchLimitOrder[] memory orders = new ExclusiveDutchLimitOrder[](2);
        orders[0] = ExclusiveDutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });
        orders[1] = ExclusiveDutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(address(tokenIn), inputAmount * 2, inputAmount * 2),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, maker)
        });

        vm.expectRevert();
        reactor.executeBatch(generateSignedOrders(orders), address(fillContract), bytes(""));
    }

    // Execute 2 dutch limit orders, but executor does not send enough output tokens to the recipient
    // should fail with InsufficientOutput error from balance checks
    function testExecuteBatchInsufficientOutputSent() public {
        MockFillContractWithOutputOverride fill = new MockFillContractWithOutputOverride();
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount * 3);
        tokenOut.mint(address(fill), 5 * 10 ** 18);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        ExclusiveDutchLimitOrder[] memory orders = new ExclusiveDutchLimitOrder[](2);
        orders[0] = ExclusiveDutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });
        orders[1] = ExclusiveDutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(address(tokenIn), inputAmount * 2, inputAmount * 2),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, maker)
        });

        fill.setOutputAmount(outputAmount);
        vm.expectRevert(ExpectedBalanceLib.InsufficientOutput.selector);
        reactor.executeBatch(generateSignedOrders(orders), address(fill), bytes(""));
    }

    // Execute 2 dutch limit orders, but executor does not send enough output ETH to the recipient
    // should fail with InsufficientOutput error from balance checks
    function testExecuteBatchInsufficientOutputSentNative() public {
        MockFillContractWithOutputOverride fill = new MockFillContractWithOutputOverride();
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = inputAmount;

        tokenIn.mint(address(maker), inputAmount * 2);
        vm.deal(address(fill), 2 * 10 ** 18);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        ExclusiveDutchLimitOrder[] memory orders = new ExclusiveDutchLimitOrder[](2);
        orders[0] = ExclusiveDutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, maker)
        });
        orders[1] = ExclusiveDutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 300,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, maker)
        });

        fill.setOutputAmount(outputAmount / 2);
        vm.expectRevert(ExpectedBalanceLib.InsufficientOutput.selector);
        reactor.executeBatch(generateSignedOrders(orders), address(fill), bytes(""));
    }

    function generateSignedOrders(ExclusiveDutchLimitOrder[] memory orders)
        private
        view
        returns (SignedOrder[] memory result)
    {
        result = new SignedOrder[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            bytes memory sig = signOrder(makerPrivateKey, address(permit2), orders[i]);
            result[i] = SignedOrder(abi.encode(orders[i]), sig);
        }
    }
}

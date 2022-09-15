// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {UniswapV3Executor} from "../../src/sample-executors/UniswapV3Executor.sol";
import {DutchLimitOrderReactor, DutchLimitOrder} from "../../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockSwapRouter} from "../util/mock/MockSwapRouter.sol";
import {Output, TokenAmount, OrderInfo, ResolvedOrder, Signature, SignedOrder} from "../../src/lib/ReactorStructs.sol";
import {IUniV3SwapRouter} from "../../src/external/IUniV3SwapRouter.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

// This set of tests will use a mock swap router to simulate the Uniswap swap router.
contract UniswapV3ExecutorTest is Test, PermitSignature, GasSnapshot {
    using OrderInfoBuilder for OrderInfo;

    uint256 takerPrivateKey;
    uint256 makerPrivateKey;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    address taker;
    address maker;
    UniswapV3Executor uniswapV3Executor;
    MockSwapRouter mockSwapRouter;
    DutchLimitOrderReactor dloReactor;
    PermitPost permitPost;

    uint256 constant ONE = 10 ** 18;
    // Represents a 0.3% fee, but setting this doesn't matter
    uint24 constant FEE = 3000;
    bytes32 constant TRANSFER_EVENT_SIG = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    bytes32 constant APPROVAL_EVENT_SIG = 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;
    bytes32 constant FILL_EVENT_SIG = 0xba7599121d7877246723714eb403e13928cdbebe980abf7c630c0f9bef83fce1;

    function setUp() public {
        vm.warp(1660671678);

        // Mock input/output tokens
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);

        // Mock taker and maker
        takerPrivateKey = 0x12341234;
        taker = vm.addr(takerPrivateKey);
        makerPrivateKey = 0x12341235;
        maker = vm.addr(makerPrivateKey);

        // Instantiate relevant contracts
        mockSwapRouter = new MockSwapRouter();
        uniswapV3Executor = new UniswapV3Executor(address(mockSwapRouter));
        permitPost = new PermitPost();
        dloReactor = new DutchLimitOrderReactor(address(permitPost));

        // Do appropriate max approvals
        tokenIn.forceApprove(maker, address(permitPost), type(uint256).max);
    }

    function testReactorCallback() public {
        Output[] memory outputs = new Output[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        bytes memory fillData = abi.encode(FEE);
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            TokenAmount(address(tokenIn), ONE),
            outputs
        );
        tokenIn.mint(address(uniswapV3Executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        uniswapV3Executor.reactorCallback(resolvedOrders, fillData);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), ONE);
        assertEq(tokenOut.balanceOf(address(uniswapV3Executor)), ONE);
    }

    // Output will resolve to 0.5. Input = 1. SwapRouter exchanges at 1 to 1 rate.
    // There will be 0.5 output token remaining in UniswapV3Executor.
    function testExecute() public {
        uint256 inputAmount = ONE;
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        tokenIn.mint(maker, inputAmount);
        tokenOut.mint(address(mockSwapRouter), ONE);

        vm.recordLogs();
        snapStart("DutchUniswapV3ExecuteSingle");
        dloReactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash)
            ),
            address(uniswapV3Executor),
            abi.encode(FEE)
        );
        snapEnd();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // There will be 7 events in the following order: Transfer, Approval, Transfer,
        // Transfer, Approval, Transfer, Fill
        assertEq(entries.length, 7);
        assertEq(entries[0].topics[0], TRANSFER_EVENT_SIG);
        assertEq(entries[1].topics[0], APPROVAL_EVENT_SIG);
        assertEq(entries[2].topics[0], TRANSFER_EVENT_SIG);
        assertEq(entries[3].topics[0], TRANSFER_EVENT_SIG);
        assertEq(entries[4].topics[0], APPROVAL_EVENT_SIG);
        assertEq(entries[5].topics[0], TRANSFER_EVENT_SIG);
        assertEq(entries[6].topics[0], FILL_EVENT_SIG);

        assertEq(tokenIn.balanceOf(maker), 0);
        assertEq(tokenIn.balanceOf(address(uniswapV3Executor)), 0);
        assertEq(tokenOut.balanceOf(maker), 500000000000000000);
        assertEq(tokenOut.balanceOf(address(uniswapV3Executor)), 500000000000000000);
    }

    // The exact same as `testExecute`, however there will be 2 less approval events
    // because we have pre approved input and output token to appropriate spenders.
    function testExecutePreApprovals() public {
        uint256 inputAmount = ONE;
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        tokenIn.mint(maker, inputAmount);
        tokenOut.mint(address(mockSwapRouter), ONE);
        // Do pre approvals
        tokenIn.forceApprove(address(uniswapV3Executor), address(mockSwapRouter), type(uint256).max);
        tokenOut.forceApprove(address(uniswapV3Executor), address(dloReactor), type(uint256).max);

        vm.recordLogs();
        dloReactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash)
            ),
            address(uniswapV3Executor),
            abi.encode(FEE)
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // There will be 5 events in the following order: Transfer, Transfer,
        // Transfer, Transfer, Fill
        assertEq(entries.length, 5);
        assertEq(entries[0].topics[0], TRANSFER_EVENT_SIG);
        assertEq(entries[1].topics[0], TRANSFER_EVENT_SIG);
        assertEq(entries[2].topics[0], TRANSFER_EVENT_SIG);
        assertEq(entries[3].topics[0], TRANSFER_EVENT_SIG);
        assertEq(entries[4].topics[0], FILL_EVENT_SIG);

        assertEq(tokenIn.balanceOf(maker), 0);
        assertEq(tokenIn.balanceOf(address(uniswapV3Executor)), 0);
        assertEq(tokenOut.balanceOf(maker), 500000000000000000);
        assertEq(tokenOut.balanceOf(address(uniswapV3Executor)), 500000000000000000);
    }

    // Requested output = 2 & input = 1. SwapRouter swaps at 1 to 1 rate, so there will
    // there will be an overflow error when reactor tries to transfer 2 outputToken out of fill contract.
    function testExecuteInsufficientOutput() public {
        uint256 inputAmount = ONE;
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            // The output will resolve to 2
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE * 2, ONE * 2, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        tokenIn.mint(maker, inputAmount);
        tokenOut.mint(address(mockSwapRouter), ONE * 2);

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        dloReactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash)
            ),
            address(uniswapV3Executor),
            abi.encode(FEE)
        );
    }

    // Requested outputs = 2 & 1 (for a total output of 3), input = 3. With
    // swap rate at 1 to 1, at the end of the test there will be 3 tokenIn
    // in mockSwapRouter and 3 tokenOut in maker.
    function testExecuteMultipleOutputs() public {
        uint256 inputAmount = ONE * 3;
        uint256[] memory startAmounts = new uint256[](2);
        startAmounts[0] = ONE * 2;
        startAmounts[1] = ONE;
        uint256[] memory endAmounts = new uint256[](2);
        endAmounts[0] = startAmounts[0];
        endAmounts[1] = startAmounts[1];
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts, endAmounts, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        tokenIn.mint(maker, inputAmount);
        tokenOut.mint(address(mockSwapRouter), ONE * 3);

        dloReactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash)
            ),
            address(uniswapV3Executor),
            abi.encode(FEE)
        );

        assertEq(tokenIn.balanceOf(maker), 0);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), ONE * 3);
        assertEq(tokenIn.balanceOf(address(uniswapV3Executor)), 0);
        assertEq(tokenOut.balanceOf(maker), ONE * 3);
        assertEq(tokenOut.balanceOf(address(uniswapV3Executor)), 0);
    }

    // Requested outputs = 2 & 1 (for a total output of 3), input = 2. With
    // swap rate at 1 to 1, there is insufficient input. The code will overflow error when reactor
    // tries to withdraw the second output of 1 from the fill contract.
    function testExecuteMultipleOutputsInsufficientInput() public {
        uint256 inputAmount = ONE * 2;
        uint256[] memory startAmounts = new uint256[](2);
        startAmounts[0] = ONE * 2;
        startAmounts[1] = ONE;
        uint256[] memory endAmounts = new uint256[](2);
        endAmounts[0] = startAmounts[0];
        endAmounts[1] = startAmounts[1];
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts, endAmounts, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        tokenIn.mint(maker, inputAmount);
        tokenOut.mint(address(mockSwapRouter), ONE * 3);

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        dloReactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash)
            ),
            address(uniswapV3Executor),
            abi.encode(FEE)
        );
    }

    // Two orders, first one has input = 1 and outputs = [1]. Second one has input = 3
    // and outputs = [2]. Mint maker 10 input and mint mockSwapRouter 10 output. After
    // the execution, maker should have 6 input / 3 output, mockSwapRouter should have
    // 4 input / 6 output, and uniswapV3Executor should have 0 input / 1 output.
    function testExecuteBatch() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = inputAmount;

        tokenIn.mint(address(maker), inputAmount * 10);
        tokenOut.mint(address(mockSwapRouter), outputAmount * 10);
        tokenIn.forceApprove(maker, address(permitPost), type(uint256).max);

        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });
        Signature memory sig1 = signOrder(
            vm, makerPrivateKey, address(permitPost), order1.info, order1.input, keccak256(abi.encode(order1))
        );
        signedOrders[0] = SignedOrder(abi.encode(order1), sig1);

        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withNonce(1),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount * 3),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, maker)
        });
        Signature memory sig2 = signOrder(
            vm, makerPrivateKey, address(permitPost), order2.info, order2.input, keccak256(abi.encode(order2))
        );
        signedOrders[1] = SignedOrder(abi.encode(order2), sig2);

        snapStart("DutchUniswapV3ExecuteBatch");
        dloReactor.executeBatch(signedOrders, address(uniswapV3Executor), abi.encode(FEE));
        snapEnd();
        assertEq(tokenOut.balanceOf(maker), 3 * 10 ** 18);
        assertEq(tokenIn.balanceOf(maker), 6 * 10 ** 18);
        assertEq(tokenOut.balanceOf(address(mockSwapRouter)), 6 * 10 ** 18);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), 4 * 10 ** 18);
        assertEq(tokenOut.balanceOf(address(uniswapV3Executor)), 1 * 10 ** 18);
        assertEq(tokenIn.balanceOf(address(uniswapV3Executor)), 0);
    }
}

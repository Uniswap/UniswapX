// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Executor} from "../../src/sample-executors/UniswapV3Executor.sol";
import {DutchLimitOrderReactor, DutchLimitOrder} from "../../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockSwapRouter} from "../util/mock/MockSwapRouter.sol";
import {Output, TokenAmount, OrderInfo, ResolvedOrder} from "../../src/lib/ReactorStructs.sol";
import {IUniV3SwapRouter} from "../../src/external/IUniV3SwapRouter.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

// This set of tests will use a mock swap router to simulate the Uniswap swap router.
contract UniswapV3ExecutorTest is Test, PermitSignature {
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
    // There will be 0.5 input token remaining in UniswapV3Executor.
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

        dloReactor.execute(
            order,
            getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({token: address(tokenIn), spender: address(dloReactor), maxAmount: inputAmount, deadline: order.info.deadline}),
                0,
                uint256(orderHash)
            ),
            address(uniswapV3Executor),
            abi.encode(FEE)
        );

        assertEq(tokenIn.balanceOf(maker), 0);
        assertEq(tokenIn.balanceOf(address(uniswapV3Executor)), 500000000000000000);
        assertEq(tokenOut.balanceOf(maker), 500000000000000000);
        assertEq(tokenOut.balanceOf(address(uniswapV3Executor)), 0);
    }

    // Requested output = 2 & input = 1. SwapRouter swaps at 1 to 1 rate, so there will
    // be insufficient input.
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

        vm.expectRevert("Too much requested");
        dloReactor.execute(
            order,
            getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({token: address(tokenIn), spender: address(dloReactor), maxAmount: inputAmount, deadline: order.info.deadline}),
                0,
                uint256(orderHash)
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
            order,
            getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({token: address(tokenIn), spender: address(dloReactor), maxAmount: inputAmount, deadline: order.info.deadline}),
                0,
                uint256(orderHash)
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
    // swap rate at 1 to 1, there is insufficient input.
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

        vm.expectRevert("Too much requested");
        dloReactor.execute(
            order,
            getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({token: address(tokenIn), spender: address(dloReactor), maxAmount: inputAmount, deadline: order.info.deadline}),
                0,
                uint256(orderHash)
            ),
            address(uniswapV3Executor),
            abi.encode(FEE)
        );
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Executor} from "../../src/sample-executors/UniswapV3Executor.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchLimitOrderExecution} from "../../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {MockERC20} from "../../src/test/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockSwapRouter} from "../../src/test/MockSwapRouter.sol";
import {Output, TokenAmount, OrderInfo} from "../../src/interfaces/ReactorStructs.sol";
import {IUniV3SwapRouter} from "../../src/external/IUniV3SwapRouter.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import "forge-std/console.sol";

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
        bytes memory fillData = abi.encode(tokenIn, FEE, ONE, dloReactor);
        tokenIn.mint(address(uniswapV3Executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        uniswapV3Executor.reactorCallback(outputs, fillData);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), ONE);
        assertEq(tokenOut.balanceOf(address(uniswapV3Executor)), ONE);
    }

    // Output will resolve to 0.5. Input = 1. SwapRouter exchanges at 1 to 1 rate.
    // There will be 0.5 input token remaining in UniswapV3Executor.
    function testExecute() public {
        uint inputAmount = ONE;
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        DutchLimitOrderExecution memory execution = DutchLimitOrderExecution({
            order: order,
            sig: getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({
                    token: address(tokenIn),
                    spender: address(dloReactor),
                    maxAmount: inputAmount,
                    deadline: order.info.deadline
                }),
                0,
                uint256(orderHash)
            ),
            fillContract: address(uniswapV3Executor),
            fillData: abi.encode(tokenIn, FEE, inputAmount, dloReactor)
        });

        tokenIn.mint(maker, inputAmount);
        tokenOut.mint(address(mockSwapRouter), ONE);

        dloReactor.execute(execution);

        assertEq(tokenIn.balanceOf(maker), 0);
        assertEq(tokenIn.balanceOf(address(uniswapV3Executor)), 500000000000000000);
        assertEq(tokenOut.balanceOf(maker), 500000000000000000);
        assertEq(tokenOut.balanceOf(address(uniswapV3Executor)), 0);
    }

    // Requested output = 2 & input = 1. SwapRouter swaps at 1 to 1 rate, so there will
    // be insufficient input.
    function testExecuteInsufficientOutput() public {
        uint inputAmount = ONE;
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            // The output will resolve to 2
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE * 2, ONE * 2, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        DutchLimitOrderExecution memory execution = DutchLimitOrderExecution({
        order: order,
        sig: getPermitSignature(
            vm,
            makerPrivateKey,
            address(permitPost),
            Permit({
                token: address(tokenIn),
                spender: address(dloReactor),
                maxAmount: inputAmount,
                deadline: order.info.deadline
            }),
            0,
            uint256(orderHash)
        ),
        fillContract: address(uniswapV3Executor),
        fillData: abi.encode(tokenIn, FEE, inputAmount, dloReactor)
        });

        tokenIn.mint(maker, inputAmount);
        tokenOut.mint(address(mockSwapRouter), ONE * 2);

        vm.expectRevert("Too much requested");
        dloReactor.execute(execution);
    }

    // Encode the wrong inputToken in fillData. This code will error in the transferFrom()
    // in MockSwapRouter, resulting in "Arithmetic over/underflow", which is 0x11 error
    function testExecuteWrongFillDataToken() public {
        uint inputAmount = ONE;
        DutchLimitOrder memory order = DutchLimitOrder({
        info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
        startTime: block.timestamp - 100,
        endTime: block.timestamp + 100,
        input: TokenAmount(address(tokenIn), inputAmount),
        outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        DutchLimitOrderExecution memory execution = DutchLimitOrderExecution({
            order: order,
            sig: getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({
                    token: address(tokenIn),
                    spender: address(dloReactor),
                    maxAmount: inputAmount,
                    deadline: order.info.deadline
                }),
                0,
                uint256(orderHash)
                ),
            fillContract: address(uniswapV3Executor),
            fillData: abi.encode(tokenOut, FEE, inputAmount, dloReactor)
        });

        tokenIn.mint(maker, inputAmount);
        tokenOut.mint(address(mockSwapRouter), ONE);

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        dloReactor.execute(execution);
    }

    // Encode the wrong reactor in fillData. Will error in the reactor's code to
    // transfer output tokens to recipients because executor has approved the incorrect
    // reactor.
    function testExecuteWrongFillDataReactor() public {
        uint inputAmount = ONE;
        DutchLimitOrder memory order = DutchLimitOrder({
        info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
        startTime: block.timestamp - 100,
        endTime: block.timestamp + 100,
        input: TokenAmount(address(tokenIn), inputAmount),
        outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        DutchLimitOrderExecution memory execution = DutchLimitOrderExecution({
            order: order,
            sig: getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({
                    token: address(tokenIn),
                    spender: address(dloReactor),
                    maxAmount: inputAmount,
                    deadline: order.info.deadline
                }),
                    0,
                    uint256(orderHash)
                ),
            fillContract: address(uniswapV3Executor),
            fillData: abi.encode(tokenIn, FEE, inputAmount, address(0))
        });

        tokenIn.mint(maker, inputAmount);
        tokenOut.mint(address(mockSwapRouter), ONE);

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        dloReactor.execute(execution);
    }
}

contract UniswapV3ExecutorIntegrationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address swapRouter02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    // .env's PRIVATE_KEY corresponds to this address
    address maker = 0x3580F45Cd5DB00221A999ae2925122ACcccDf254;
    UniswapV3Executor uniswapV3Executor;
    PermitPost permitPost;
    DutchLimitOrderReactor dloReactor;

    function setUp() public {
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 15327550);
        uniswapV3Executor = new UniswapV3Executor(swapRouter02);
        permitPost = new PermitPost();
        dloReactor = new DutchLimitOrderReactor(address(permitPost));

        // Maker max approves permit post
        vm.prank(maker);
        ERC20(weth).approve(address(permitPost), type(uint256).max);

        // Transfer 0.02 WETH to maker
        vm.prank(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        ERC20(weth).transfer(maker, 20000000000000000);
    }

    // Maker's order consists of input = 0.02WETH & output = 30 USDC. There will be 4025725858800932
    // excess wei of USDC in uniswapV3Executor
    function testExecute() public {
        uint inputAmount = 20000000000000000;
        uint24 fee = 3000;

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(weth), inputAmount),
            outputs: OutputsBuilder.singleDutch(address(usdc), 30000000, 30000000, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        DutchLimitOrderExecution memory execution = DutchLimitOrderExecution({
            order: order,
            sig: getPermitSignature(
                vm,
                vm.envUint("PRIVATE_KEY"),
                address(permitPost),
                Permit({
                    token: address(weth),
                    spender: address(dloReactor),
                    maxAmount: inputAmount,
                    deadline: order.info.deadline
                }),
                0,
                uint256(orderHash)
            ),
            fillContract: address(uniswapV3Executor),
            fillData: abi.encode(weth, fee, inputAmount, dloReactor)
        });

        assertEq(ERC20(weth).balanceOf(maker), 20000000000000000);
        assertEq(ERC20(usdc).balanceOf(maker), 0);
        assertEq(ERC20(weth).balanceOf(address(uniswapV3Executor)), 0);
        dloReactor.execute(execution);
        assertEq(ERC20(weth).balanceOf(maker), 0);
        assertEq(ERC20(usdc).balanceOf(maker), 30000000);
        assertEq(ERC20(weth).balanceOf(address(uniswapV3Executor)), 4025725858800932);
    }
}
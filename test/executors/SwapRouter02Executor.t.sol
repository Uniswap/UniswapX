// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SwapRouter02Executor} from "../../src/sample-executors/SwapRouter02Executor.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchInput,
    DutchOutput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {MockSwapRouter} from "../util/mock/MockSwapRouter.sol";
import {OutputToken, InputToken, OrderInfo, ResolvedOrder, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ISwapRouter02} from "../../src/external/ISwapRouter02.sol";
import {IUniV3SwapRouter} from "../../src/external/IUniV3SwapRouter.sol";

// This set of tests will use a mock swap router to simulate the Uniswap swap router.
contract SwapRouter02ExecutorTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;

    uint256 takerPrivateKey;
    uint256 makerPrivateKey;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    WETH weth;
    address taker;
    address maker;
    SwapRouter02Executor swapRouter02Executor;
    MockSwapRouter mockSwapRouter;
    DutchLimitOrderReactor reactor;
    ISignatureTransfer permit2;

    uint256 constant ONE = 10 ** 18;
    // Represents a 0.3% fee, but setting this doesn't matter
    uint24 constant FEE = 3000;
    address constant PROTOCOL_FEE_RECIPIENT = address(80085);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    // to test sweeping ETH
    receive() external payable {}

    function setUp() public {
        vm.warp(1000);

        // Mock input/output tokens
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        weth = new WETH();

        // Mock taker and maker
        takerPrivateKey = 0x12341234;
        taker = vm.addr(takerPrivateKey);
        makerPrivateKey = 0x12341235;
        maker = vm.addr(makerPrivateKey);

        // Instantiate relevant contracts
        mockSwapRouter = new MockSwapRouter(address(weth));
        permit2 = ISignatureTransfer(deployPermit2());
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        swapRouter02Executor =
        new SwapRouter02Executor(address(this), address(reactor), address(this), ISwapRouter02(address(mockSwapRouter)));

        // Do appropriate max approvals
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);
    }

    function testReactorCallback() public {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        outputs[0].recipient = maker;
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);
        bytes memory fillData = abi.encode(tokensToApproveForSwapRouter02, multicallData);

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            InputToken(address(tokenIn), ONE, ONE),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );
        tokenIn.mint(address(swapRouter02Executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        vm.prank(address(reactor));
        swapRouter02Executor.reactorCallback(resolvedOrders, address(this), fillData);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), ONE);
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), 0);
        assertEq(tokenOut.balanceOf(address(maker)), ONE);
    }

    // Output will resolve to 0.5. Input = 1. SwapRouter exchanges at 1 to 1 rate.
    // There will be 0.5 output token remaining in SwapRouter02Executor.
    function testExecute() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(maker))
        });

        tokenIn.mint(maker, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );

        assertEq(tokenIn.balanceOf(maker), 0);
        assertEq(tokenIn.balanceOf(address(swapRouter02Executor)), 0);
        assertEq(tokenOut.balanceOf(maker), ONE / 2);
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), ONE / 2);
    }

    // Requested output = 2 & input = 1. SwapRouter swaps at 1 to 1 rate, so there will
    // there will be an overflow error when reactor tries to transfer 2 outputToken out of fill contract.
    function testExecuteInsufficientOutput() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            // The output will resolve to 2
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE * 2, ONE * 2, address(maker))
        });

        tokenIn.mint(maker, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE * 2);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        vm.expectRevert("TRANSFER_FAILED");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
    }

    // There is one order with outputs of length 3. 1st output = 2 token out to maker, 2nd output = 1 token out to
    // maker, 3rd output = 1 token out as a fee with recipient = address(1). At the end of the test, there will
    // be 4 tokenIn in mockSwapRouter, 3 tokenOut in maker, and 1 tokenOut in reactor.
    function testExecuteOneOrderWithMultipleOutputs() public {
        uint256 inputAmount = ONE * 4;
        uint256[] memory startAmounts = new uint256[](3);
        startAmounts[0] = ONE * 2;
        startAmounts[1] = ONE;
        startAmounts[2] = ONE;
        uint256[] memory endAmounts = new uint256[](3);
        endAmounts[0] = startAmounts[0];
        endAmounts[1] = startAmounts[1];
        endAmounts[2] = startAmounts[2];
        DutchOutput[] memory outputs =
            OutputsBuilder.multipleDutch(address(tokenOut), startAmounts, endAmounts, address(maker));
        // fee output
        outputs[2].recipient = address(1);
        outputs[2].isFeeOutput = true;

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: outputs
        });

        tokenIn.mint(maker, inputAmount);
        tokenOut.mint(address(mockSwapRouter), ONE * 4);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: inputAmount,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );

        assertEq(tokenIn.balanceOf(maker), 0);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), ONE * 4);
        assertEq(tokenIn.balanceOf(address(swapRouter02Executor)), 0);
        assertEq(tokenOut.balanceOf(maker), ONE * 3);
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), 0);

        // assert fees properly handled
        assertEq(tokenOut.balanceOf(address(reactor)), ONE);
        assertEq(reactor.feesOwed(address(tokenOut), address(1)), ONE / 2);
        assertEq(reactor.feesOwed(address(tokenOut), address(0)), ONE / 2);
    }

    // Two orders, first one has input = 1 and outputs = [1]. Second one has input = 3
    // and outputs = [2]. Mint maker 10 input and mint mockSwapRouter 10 output. After
    // the execution, maker should have 6 input / 3 output, mockSwapRouter should have
    // 4 input / 6 output, and swapRouter02Executor should have 0 input / 1 output.
    function testExecuteBatch() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = inputAmount;

        tokenIn.mint(address(maker), inputAmount * 10);
        tokenOut.mint(address(mockSwapRouter), outputAmount * 10);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });
        bytes memory sig1 = signOrder(makerPrivateKey, address(permit2), order1);
        signedOrders[0] = SignedOrder(abi.encode(order1), sig1);

        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount * 3, inputAmount * 3),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, maker)
        });
        bytes memory sig2 = signOrder(makerPrivateKey, address(permit2), order2);
        signedOrders[1] = SignedOrder(abi.encode(order2), sig2);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: inputAmount * 4,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        reactor.executeBatch(
            signedOrders, swapRouter02Executor, abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
        assertEq(tokenOut.balanceOf(maker), 3 ether);
        assertEq(tokenIn.balanceOf(maker), 6 ether);
        assertEq(tokenOut.balanceOf(address(mockSwapRouter)), 6 ether);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), 4 ether);
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), 10 ** 18);
        assertEq(tokenIn.balanceOf(address(swapRouter02Executor)), 0);
    }

    function testNotWhitelistedCaller() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(maker))
        });

        tokenIn.mint(maker, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        vm.prank(address(0xbeef));
        vm.expectRevert(SwapRouter02Executor.CallerNotWhitelisted.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
    }

    // Very similar to `testReactorCallback`, but do not vm.prank the reactor when calling `reactorCallback`, so reverts
    // in
    function testMsgSenderNotReactor() public {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);
        bytes memory fillData = abi.encode(tokensToApproveForSwapRouter02, multicallData);

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            InputToken(address(tokenIn), ONE, ONE),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );
        tokenIn.mint(address(swapRouter02Executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        vm.expectRevert(SwapRouter02Executor.MsgSenderNotReactor.selector);
        swapRouter02Executor.reactorCallback(resolvedOrders, address(this), fillData);
    }

    function testUnwrapWETH() public {
        vm.deal(address(weth), 1 ether);
        deal(address(weth), address(swapRouter02Executor), ONE);
        uint256 balanceBefore = address(this).balance;
        swapRouter02Executor.unwrapWETH(address(this));
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function testUnwrapWETHNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xbeef));
        swapRouter02Executor.unwrapWETH(address(this));
    }

    function testWithdrawETH() public {
        vm.deal(address(swapRouter02Executor), 1 ether);
        uint256 balanceBefore = address(this).balance;
        swapRouter02Executor.withdrawETH(address(this));
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function testWithdrawETHNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xbeef));
        swapRouter02Executor.withdrawETH(address(this));
    }
}

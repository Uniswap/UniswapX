// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MultiFillerSwapRouter02Executor} from "../../src/sample-executors/MultiFillerSwapRouter02Executor.sol";
import {DutchOrderReactor, DutchOrder, DutchInput, DutchOutput} from "../../src/reactors/DutchOrderReactor.sol";
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
contract MultiFillerSwapRouter02ExecutorTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;

    uint256 fillerPrivateKey;
    uint256 swapperPrivateKey;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    WETH weth;
    address filler;
    address swapper;
    MultiFillerSwapRouter02Executor multiFillerSwapRouter02Executor;
    MockSwapRouter mockSwapRouter;
    DutchOrderReactor reactor;
    ISignatureTransfer permit2;

    // mock whitelisted callers
    address[10] whitelistedFillers = [
        address(this),
        address(0x1),
        address(0x2),
        address(0x3),
        address(0x4),
        address(0x5),
        address(0x6),
        address(0x7),
        address(0x8),
        address(0x9)
    ];

    uint256 constant ONE = 10 ** 18;
    // Represents a 0.3% fee, but setting this doesn't matter
    uint24 constant FEE = 3000;
    address constant PROTOCOL_FEE_OWNER = address(80085);

    // to test sweeping ETH
    receive() external payable {}

    function setUp() public {
        vm.warp(1000);

        // Mock input/output tokens
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        weth = new WETH();

        // Mock filler and swapper
        fillerPrivateKey = 0x12341234;
        filler = vm.addr(fillerPrivateKey);
        swapperPrivateKey = 0x12341235;
        swapper = vm.addr(swapperPrivateKey);

        // Instantiate relevant contracts
        mockSwapRouter = new MockSwapRouter(address(weth));
        permit2 = ISignatureTransfer(deployPermit2());
        reactor = new DutchOrderReactor(address(permit2), PROTOCOL_FEE_OWNER);
        multiFillerSwapRouter02Executor =
        new MultiFillerSwapRouter02Executor(address(reactor), address(this), ISwapRouter02(address(mockSwapRouter)), whitelistedFillers);

        // Do appropriate max approvals
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
    }

    function testReactorCallback() public {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        outputs[0].recipient = swapper;
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(multiFillerSwapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);
        bytes memory fillData = abi.encode(tokensToApproveForSwapRouter02, multicallData);

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            InputToken(tokenIn, ONE, ONE),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );
        tokenIn.mint(address(multiFillerSwapRouter02Executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        vm.prank(address(reactor));
        multiFillerSwapRouter02Executor.reactorCallback(resolvedOrders, address(this), fillData);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), ONE);
        assertEq(tokenOut.balanceOf(address(multiFillerSwapRouter02Executor)), 0);
        assertEq(tokenOut.balanceOf(address(swapper)), ONE);
    }

    // Output will resolve to 0.5. Input = 1. SwapRouter exchanges at 1 to 1 rate.
    // There will be 0.5 output token remaining in SwapRouter02Executor.
    function testExecute() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
        });

        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(multiFillerSwapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            multiFillerSwapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenIn.balanceOf(address(multiFillerSwapRouter02Executor)), 0);
        assertEq(tokenOut.balanceOf(swapper), ONE / 2);
        assertEq(tokenOut.balanceOf(address(multiFillerSwapRouter02Executor)), ONE / 2);
    }

    // Requested output = 2 & input = 1. SwapRouter swaps at 1 to 1 rate, so there will
    // there will be an overflow error when reactor tries to transfer 2 outputToken out of fill contract.
    function testExecuteInsufficientOutput() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            // The output will resolve to 2
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE * 2, ONE * 2, address(swapper))
        });

        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE * 2);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(multiFillerSwapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        vm.expectRevert("TRANSFER_FAILED");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            multiFillerSwapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
    }

    // Two orders, first one has input = 1 and outputs = [1]. Second one has input = 3
    // and outputs = [2]. Mint swapper 10 input and mint mockSwapRouter 10 output. After
    // the execution, swapper should have 6 input / 3 output, mockSwapRouter should have
    // 4 input / 6 output, and multiFillerSwapRouter02Executor should have 0 input / 1 output.
    function testExecuteBatch() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 10);
        tokenOut.mint(address(mockSwapRouter), outputAmount * 10);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });
        bytes memory sig1 = signOrder(swapperPrivateKey, address(permit2), order1);
        signedOrders[0] = SignedOrder(abi.encode(order1), sig1);

        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount * 3, inputAmount * 3),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, swapper)
        });
        bytes memory sig2 = signOrder(swapperPrivateKey, address(permit2), order2);
        signedOrders[1] = SignedOrder(abi.encode(order2), sig2);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(multiFillerSwapRouter02Executor),
            amountIn: inputAmount * 4,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        reactor.executeBatch(
            signedOrders, multiFillerSwapRouter02Executor, abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
        assertEq(tokenOut.balanceOf(swapper), 3 ether);
        assertEq(tokenIn.balanceOf(swapper), 6 ether);
        assertEq(tokenOut.balanceOf(address(mockSwapRouter)), 6 ether);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), 4 ether);
        assertEq(tokenOut.balanceOf(address(multiFillerSwapRouter02Executor)), 10 ** 18);
        assertEq(tokenIn.balanceOf(address(multiFillerSwapRouter02Executor)), 0);
    }

    function testNotWhitelistedCaller() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
        });

        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(multiFillerSwapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        vm.prank(address(0xbeef));
        vm.expectRevert(MultiFillerSwapRouter02Executor.CallerNotWhitelisted.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            multiFillerSwapRouter02Executor,
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
            recipient: address(multiFillerSwapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);
        bytes memory fillData = abi.encode(tokensToApproveForSwapRouter02, multicallData);

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            InputToken(tokenIn, ONE, ONE),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );
        tokenIn.mint(address(multiFillerSwapRouter02Executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        vm.expectRevert(MultiFillerSwapRouter02Executor.MsgSenderNotReactor.selector);
        multiFillerSwapRouter02Executor.reactorCallback(resolvedOrders, address(this), fillData);
    }

    function testUnwrapWETH() public {
        vm.deal(address(weth), 1 ether);
        deal(address(weth), address(multiFillerSwapRouter02Executor), ONE);
        uint256 balanceBefore = address(this).balance;
        multiFillerSwapRouter02Executor.unwrapWETH(address(this));
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function testUnwrapWETHNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xbeef));
        multiFillerSwapRouter02Executor.unwrapWETH(address(this));
    }

    function testWithdrawETH() public {
        vm.deal(address(multiFillerSwapRouter02Executor), 1 ether);
        uint256 balanceBefore = address(this).balance;
        multiFillerSwapRouter02Executor.withdrawETH(address(this));
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function testWithdrawETHNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xbeef));
        multiFillerSwapRouter02Executor.withdrawETH(address(this));
    }
}

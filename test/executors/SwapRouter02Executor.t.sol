// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

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

    function setUp() public {
        vm.warp(1000);

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
        permit2 = ISignatureTransfer(deployPermit2());
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        swapRouter02Executor =
            new SwapRouter02Executor(address(this), address(reactor), address(this), address(mockSwapRouter));

        // Do appropriate max approvals
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);
    }

    function testReactorCallback() public {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(tokenOut);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);
        bytes memory fillData = abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData);

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
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), ONE);
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
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(tokenOut);

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
            address(swapRouter02Executor),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
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
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(tokenOut);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(swapRouter02Executor),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
        );
    }
}

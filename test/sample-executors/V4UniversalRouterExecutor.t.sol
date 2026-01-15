// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {DeployPermit2} from "../util/DeployPermit2.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";

import {Reactor} from "../../src/v4/Reactor.sol";
import {IReactor} from "../../src/v4/interfaces/IReactor.sol";
import {OrderInfo, ResolvedOrder} from "../../src/v4/base/ReactorStructs.sol";
import {SignedOrder, InputToken} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../v4/util/OrderInfoBuilder.sol";
import {MockAuctionResolver} from "../v4/util/mock/MockAuctionResolver.sol";
import {MockOrder, MockOrderLib} from "../v4/util/mock/MockOrderLib.sol";
import {TokenTransferHook} from "../../src/v4/hooks/TokenTransferHook.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";

import {V4UniversalRouterExecutor} from "../../src/sample-executors/V4UniversalRouterExecutor.sol";

/// @notice Mock Universal Router for testing
contract MockUniversalRouter {
    uint256 public receivedETH;
    bool public shouldRevert;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    fallback() external payable {
        if (shouldRevert) {
            revert("Mock revert");
        }
        receivedETH = msg.value;
    }

    receive() external payable {
        if (shouldRevert) {
            revert("Mock revert");
        }
        receivedETH = msg.value;
    }
}

contract V4UniversalRouterExecutorTest is Test, PermitSignature, DeployPermit2, ReactorEvents {
    using OrderInfoBuilder for OrderInfo;
    using MockOrderLib for MockOrder;
    using SafeTransferLib for ERC20;

    uint256 constant ONE = 10 ** 18;
    address internal constant PROTOCOL_FEE_OWNER = address(1);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    IPermit2 permit2;
    Reactor reactor;
    MockAuctionResolver mockResolver;
    TokenTransferHook tokenTransferHook;
    MockUniversalRouter mockUniversalRouter;
    V4UniversalRouterExecutor executor;

    uint256 swapperPrivateKey;
    address swapper;
    address whitelistedCaller;
    address owner;

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        whitelistedCaller = makeAddr("whitelistedCaller");
        owner = makeAddr("owner");

        permit2 = IPermit2(deployPermit2());
        reactor = new Reactor(PROTOCOL_FEE_OWNER, permit2);
        mockResolver = new MockAuctionResolver();
        tokenTransferHook = new TokenTransferHook(permit2, reactor);
        mockUniversalRouter = new MockUniversalRouter();

        address[] memory whitelistedCallers = new address[](1);
        whitelistedCallers[0] = whitelistedCaller;

        executor = new V4UniversalRouterExecutor(
            whitelistedCallers, IReactor(address(reactor)), owner, address(mockUniversalRouter), permit2
        );

        // Fund executor with output tokens for fills
        tokenOut.mint(address(executor), 100 * ONE);
        vm.deal(address(executor), 100 ether);
    }

    /// @dev Create a signed order for V4 Reactor using MockOrder
    function createAndSignOrder(MockOrder memory mockOrder)
        public
        view
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        orderHash = mockOrder.witnessHash(address(mockOrder.info.auctionResolver));
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), mockOrder);
        bytes memory orderData = abi.encode(mockOrder);
        bytes memory encodedOrder = abi.encode(address(mockResolver), orderData);
        signedOrder = SignedOrder(encodedOrder, sig);
    }

    /// @dev Helper to create a basic MockOrder
    function createBasicOrder(uint256 inputAmount, uint256 outputAmount, uint256 deadline)
        internal
        view
        returns (MockOrder memory)
    {
        return MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });
    }

    /// @notice Test that the executor can fill an order through the V4 reactor
    function test_executeOrder() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(swapper, inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = createBasicOrder(inputAmount, outputAmount, deadline);
        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        uint256 swapperInputBefore = tokenIn.balanceOf(swapper);
        uint256 swapperOutputBefore = tokenOut.balanceOf(swapper);
        uint256 executorInputBefore = tokenIn.balanceOf(address(executor));
        uint256 executorOutputBefore = tokenOut.balanceOf(address(executor));

        // Prepare callback data - no approvals needed for this simple test
        address[] memory tokensToApproveForUniversalRouter = new address[](0);
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(tokenOut);
        bytes memory routerData = ""; // Empty data for mock router

        bytes memory callbackData = abi.encode(tokensToApproveForUniversalRouter, tokensToApproveForReactor, routerData);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(executor), swapper, order.info.nonce);

        vm.prank(whitelistedCaller);
        executor.execute(signedOrder, callbackData);

        assertEq(tokenIn.balanceOf(swapper), swapperInputBefore - inputAmount, "Swapper input balance incorrect");
        assertEq(tokenOut.balanceOf(swapper), swapperOutputBefore + outputAmount, "Swapper output balance incorrect");
        assertEq(
            tokenIn.balanceOf(address(executor)), executorInputBefore + inputAmount, "Executor input balance incorrect"
        );
        assertEq(
            tokenOut.balanceOf(address(executor)),
            executorOutputBefore - outputAmount,
            "Executor output balance incorrect"
        );
    }

    /// @notice Test batch execution
    function test_executeBatch() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        tokenIn.mint(swapper, inputAmount * 2);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        MockOrder[] memory orders = new MockOrder[](2);
        orders[0] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(0).withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        orders[1] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(1).withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        for (uint256 i = 0; i < orders.length; i++) {
            (SignedOrder memory signed,) = createAndSignOrder(orders[i]);
            signedOrders[i] = signed;
        }

        address[] memory tokensToApproveForUniversalRouter = new address[](0);
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(tokenOut);
        bytes memory routerData = "";

        bytes memory callbackData = abi.encode(tokensToApproveForUniversalRouter, tokensToApproveForReactor, routerData);

        uint256 swapperInputBefore = tokenIn.balanceOf(swapper);
        uint256 swapperOutputBefore = tokenOut.balanceOf(swapper);

        vm.prank(whitelistedCaller);
        executor.executeBatch(signedOrders, callbackData);

        assertEq(tokenIn.balanceOf(swapper), swapperInputBefore - inputAmount * 2, "Swapper input balance incorrect");
        assertEq(
            tokenOut.balanceOf(swapper), swapperOutputBefore + outputAmount * 2, "Swapper output balance incorrect"
        );
    }

    /// @notice Test native output (ETH) fills
    function test_executeNativeOutput() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(swapper, inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        uint256 swapperEthBefore = swapper.balance;

        address[] memory tokensToApproveForUniversalRouter = new address[](0);
        address[] memory tokensToApproveForReactor = new address[](0);
        bytes memory routerData = "";

        bytes memory callbackData = abi.encode(tokensToApproveForUniversalRouter, tokensToApproveForReactor, routerData);

        vm.prank(whitelistedCaller);
        executor.execute(signedOrder, callbackData);

        assertEq(swapper.balance, swapperEthBefore + outputAmount, "Swapper ETH balance incorrect");
    }

    /// @notice Regression: v4 reactor should refund any excess ETH back to the caller (executor),
    ///         matching BaseReactor behavior. This protects fillers from accidentally stranding ETH.
    function test_v4ReactorRefundsExcessEthToExecutor() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(swapper, inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = createBasicOrder(inputAmount, outputAmount, deadline);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        // The executor is pre-funded with ETH in setUp(). It will forward its entire ETH balance to the reactor
        // during `reactorCallback()`. The reactor must refund it back at the end of execution.
        uint256 executorEthBefore = address(executor).balance;
        uint256 reactorEthBefore = address(reactor).balance;

        address[] memory tokensToApproveForUniversalRouter = new address[](0);
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(tokenOut);
        bytes memory callbackData = abi.encode(tokensToApproveForUniversalRouter, tokensToApproveForReactor, bytes("")); // empty router data

        vm.prank(whitelistedCaller);
        executor.execute(signedOrder, callbackData);

        assertEq(address(executor).balance, executorEthBefore, "Executor should receive refunded ETH back");
        assertEq(address(reactor).balance, reactorEthBefore, "Reactor should not retain excess ETH");
    }

    /// @notice Test ERC20ETH input forwards ETH to Universal Router
    function test_ERC20ETHInputForwardsETH() public {
        address erc20ethAddress = 0x00000000e20E49e6dCeE6e8283A0C090578F0fb9;
        uint256 ethAmount = 1 ether;

        // Simulate ERC20ETH transferring ETH to executor
        vm.deal(address(executor), ethAmount);

        // Create mock resolved orders with ERC20ETH input
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0].info.reactor = IReactor(address(reactor));
        resolvedOrders[0].info.swapper = swapper;
        resolvedOrders[0].input.token = ERC20(erc20ethAddress);
        resolvedOrders[0].input.amount = ethAmount;
        resolvedOrders[0].input.maxAmount = ethAmount;

        address[] memory tokensToApproveForUniversalRouter = new address[](0);
        address[] memory tokensToApproveForReactor = new address[](0);
        bytes memory routerData = "";

        bytes memory callbackData = abi.encode(tokensToApproveForUniversalRouter, tokensToApproveForReactor, routerData);

        uint256 routerEthBefore = address(mockUniversalRouter).balance;

        vm.prank(address(reactor));
        executor.reactorCallback(resolvedOrders, callbackData);

        assertEq(mockUniversalRouter.receivedETH(), ethAmount, "Router should receive ETH");
        assertEq(
            address(mockUniversalRouter).balance, routerEthBefore + ethAmount, "Router ETH balance should increase"
        );
    }

    /// @notice Test onlyWhitelistedCaller modifier
    function test_onlyWhitelistedCaller() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        tokenIn.mint(swapper, inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = createBasicOrder(inputAmount, outputAmount, block.timestamp + 1000);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        bytes memory callbackData = abi.encode(new address[](0), new address[](0), "");

        address nonWhitelisted = makeAddr("nonWhitelisted");
        vm.prank(nonWhitelisted);
        vm.expectRevert(V4UniversalRouterExecutor.CallerNotWhitelisted.selector);
        executor.execute(signedOrder, callbackData);
    }

    /// @notice Test onlyReactor modifier
    function test_onlyReactor() public {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](0);
        bytes memory callbackData = abi.encode(new address[](0), new address[](0), "");

        address notReactor = makeAddr("notReactor");
        vm.prank(notReactor);
        vm.expectRevert(V4UniversalRouterExecutor.MsgSenderNotReactor.selector);
        executor.reactorCallback(resolvedOrders, callbackData);
    }

    /// @notice Test withdrawETH only by owner
    function test_withdrawETH() public {
        address recipient = makeAddr("recipient");
        uint256 amount = 1 ether;
        vm.deal(address(executor), amount);

        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        executor.withdrawETH(recipient);

        uint256 recipientBefore = recipient.balance;
        vm.prank(owner);
        executor.withdrawETH(recipient);
        assertEq(recipient.balance, recipientBefore + amount, "Recipient should receive ETH");
    }

    /// @notice Test withdrawERC20 only by owner
    function test_withdrawERC20() public {
        address recipient = makeAddr("recipient");
        uint256 amount = 10 * ONE;
        tokenIn.mint(address(executor), amount);

        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        executor.withdrawERC20(tokenIn, recipient);

        uint256 recipientBefore = tokenIn.balanceOf(recipient);
        vm.prank(owner);
        executor.withdrawERC20(tokenIn, recipient);
        assertEq(tokenIn.balanceOf(recipient), recipientBefore + amount, "Recipient should receive tokens");
    }

    /// @notice Test Universal Router reverts propagate correctly
    function test_universalRouterRevertPropagates() public {
        mockUniversalRouter.setShouldRevert(true);

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0].info.reactor = IReactor(address(reactor));
        resolvedOrders[0].input.token = tokenIn;
        resolvedOrders[0].input.amount = 0;

        address[] memory tokensToApproveForUniversalRouter = new address[](0);
        address[] memory tokensToApproveForReactor = new address[](0);
        bytes memory routerData = "";

        bytes memory callbackData = abi.encode(tokensToApproveForUniversalRouter, tokensToApproveForReactor, routerData);

        vm.prank(address(reactor));
        vm.expectRevert("Mock revert");
        executor.reactorCallback(resolvedOrders, callbackData);
    }

    /// @notice Test that executor can receive ETH
    function test_receiveETH() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        (bool success,) = address(executor).call{value: amount}("");
        assertTrue(success, "Should be able to send ETH to executor");
        assertEq(address(executor).balance, 100 ether + amount, "Executor should have received ETH");
    }

    /// @notice Fuzz test for execute
    function testFuzz_execute(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline > block.timestamp);
        vm.assume(inputAmount > 0);
        vm.assume(outputAmount > 0);
        vm.assume(outputAmount <= 100 * ONE); // Don't exceed executor balance

        tokenIn.mint(swapper, inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        address[] memory tokensToApproveForUniversalRouter = new address[](0);
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(tokenOut);
        bytes memory routerData = "";

        bytes memory callbackData = abi.encode(tokensToApproveForUniversalRouter, tokensToApproveForReactor, routerData);

        uint256 swapperInputBefore = tokenIn.balanceOf(swapper);
        uint256 swapperOutputBefore = tokenOut.balanceOf(swapper);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(executor), swapper, order.info.nonce);

        vm.prank(whitelistedCaller);
        executor.execute(signedOrder, callbackData);

        assertEq(tokenIn.balanceOf(swapper), swapperInputBefore - inputAmount, "Swapper input balance incorrect");
        assertEq(tokenOut.balanceOf(swapper), swapperOutputBefore + outputAmount, "Swapper output balance incorrect");
    }
}

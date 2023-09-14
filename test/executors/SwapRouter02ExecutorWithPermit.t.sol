// // SPDX-License-Identifier: GPL-2.0-or-later
// pragma solidity ^0.8.0;

// import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
// import {Test} from "forge-std/Test.sol";
// import {Vm} from "forge-std/Vm.sol";
// import {SwapRouter02Executor} from "../../src/sample-executors/SwapRouter02Executor.sol";
// import {DutchOrderReactor, DutchOrder, DutchInput, DutchOutput} from "../../src/reactors/DutchOrderReactor.sol";
// import {MockERC20} from "../util/mock/MockERC20.sol";
// import {ERC20} from "solmate/src/tokens/ERC20.sol";
// import {WETH} from "solmate/src/tokens/WETH.sol";
// import {MockSwapRouter} from "../util/mock/MockSwapRouter.sol";
// import {OutputToken, InputToken, OrderInfo, ResolvedOrder, SignedOrder} from "../../src/base/ReactorStructs.sol";
// import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
// import {DeployPermit2} from "../util/DeployPermit2.sol";
// import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
// import {OutputsBuilder} from "../util/OutputsBuilder.sol";
// import {PermitSignature} from "../util/PermitSignature.sol";
// import {ISwapRouter02, ExactInputParams} from "../../src/external/ISwapRouter02.sol";

// // This set of tests will use a mock swap router to simulate the Uniswap swap router.
// contract SwapRouter02ExecutorWithPermitTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
//     using OrderInfoBuilder for OrderInfo;

//     uint256 fillerPrivateKey;
//     uint256 swapperPrivateKey;
//     MockERC20 tokenIn;
//     MockERC20 tokenOut;
//     WETH weth;
//     address filler;
//     address swapper;
//     SwapRouter02Executor swapRouter02ExecutorWithPermit;
//     MockSwapRouter mockSwapRouter;
//     DutchOrderReactor reactor;
//     IPermit2 permit2;

//     bytes tokenInPermitData;

//     uint256 constant ONE = 10 ** 18;
//     // Represents a 0.3% fee, but setting this doesn't matter
//     uint24 constant FEE = 3000;
//     address constant PROTOCOL_FEE_OWNER = address(80085);

//     // to test sweeping ETH
//     receive() external payable {}

//     function setUp() public {
//         vm.warp(1000);

//         // Mock input/output tokens
//         tokenIn = new MockERC20("Input", "IN", 18);
//         tokenOut = new MockERC20("Output", "OUT", 18);
//         weth = new WETH();

//         // Mock filler and swapper
//         fillerPrivateKey = 0x12341234;
//         filler = vm.addr(fillerPrivateKey);
//         swapperPrivateKey = 0x12341235;
//         swapper = vm.addr(swapperPrivateKey);

//         // Instantiate relevant contracts
//         mockSwapRouter = new MockSwapRouter(address(weth));
//         permit2 = IPermit2(deployPermit2());
//         reactor = new DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
//         swapRouter02ExecutorWithPermit =
//             new SwapRouter02Executor(address(this), reactor, address(this), ISwapRouter02(address(mockSwapRouter)));

//         // sign permit for tokenIn
//         uint256 amount = type(uint256).max - 1; // infinite approval to permit2
//         uint256 deadline = type(uint256).max - 1; // never expires
//         bytes32 digest = keccak256(
//             abi.encodePacked(
//                 "\x19\x01",
//                 tokenIn.DOMAIN_SEPARATOR(),
//                 keccak256(
//                     abi.encode(
//                         keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
//                         swapper,
//                         address(permit2),
//                         amount,
//                         tokenIn.nonces(swapper),
//                         deadline
//                     )
//                 )
//             )
//         );

//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(swapperPrivateKey, digest);
//         address signer = ecrecover(digest, v, r, s);
//         assertEq(signer, swapper);

//         tokenInPermitData =
//             abi.encode(address(tokenIn), abi.encode(swapper, address(permit2), amount, deadline, v, r, s));

//         // assert that swapper has not approved P2 yet
//         assertEq(tokenIn.allowance(swapper, address(permit2)), 0);
//     }

//     // TODO: test permit reuse, permit not enough to cover

//     /// @notice no testReactorCallback test since we need to land the permit first
//     function testReactorCallback() public {}

//     function testExecuteWithoutPermit() public {
//         DutchOrder memory order = DutchOrder({
//             info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
//             decayStartTime: block.timestamp - 100,
//             decayEndTime: block.timestamp + 100,
//             input: DutchInput(tokenIn, ONE, ONE),
//             outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
//         });

//         tokenIn.mint(swapper, ONE);
//         tokenOut.mint(address(mockSwapRouter), ONE);

//         address[] memory tokensToApproveForSwapRouter02 = new address[](1);
//         tokensToApproveForSwapRouter02[0] = address(tokenIn);

//         address[] memory tokensToApproveForReactor = new address[](1);
//         tokensToApproveForReactor[0] = address(tokenOut);

//         bytes[] memory multicallData = new bytes[](1);
//         ExactInputParams memory exactInputParams = ExactInputParams({
//             path: abi.encodePacked(tokenIn, FEE, tokenOut),
//             recipient: address(swapRouter02ExecutorWithPermit),
//             amountIn: ONE,
//             amountOutMinimum: 0
//         });
//         multicallData[0] = abi.encodeWithSelector(ISwapRouter02.exactInput.selector, exactInputParams);

//         vm.expectRevert("TRANSFER_FROM_FAILED");
//         swapRouter02ExecutorWithPermit.execute(
//             SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
//             abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
//         );
//     }

//     // Output will resolve to 0.5. Input = 1. SwapRouter exchanges at 1 to 1 rate.
//     // There will be 0.5 output token remaining in SwapRouter02ExecutorWithPermit.
//     function testExecuteWithPermit() public {
//         DutchOrder memory order = DutchOrder({
//             info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
//             decayStartTime: block.timestamp - 100,
//             decayEndTime: block.timestamp + 100,
//             input: DutchInput(tokenIn, ONE, ONE),
//             outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
//         });

//         tokenIn.mint(swapper, ONE);
//         tokenOut.mint(address(mockSwapRouter), ONE);

//         address[] memory tokensToApproveForSwapRouter02 = new address[](1);
//         tokensToApproveForSwapRouter02[0] = address(tokenIn);

//         address[] memory tokensToApproveForReactor = new address[](1);
//         tokensToApproveForReactor[0] = address(tokenOut);

//         bytes[] memory multicallData = new bytes[](1);
//         ExactInputParams memory exactInputParams = ExactInputParams({
//             path: abi.encodePacked(tokenIn, FEE, tokenOut),
//             recipient: address(swapRouter02ExecutorWithPermit),
//             amountIn: ONE,
//             amountOutMinimum: 0
//         });
//         multicallData[0] = abi.encodeWithSelector(ISwapRouter02.exactInput.selector, exactInputParams);

//         snapStart("SwapRouter02ExecutorWithPermitExecute");
//         swapRouter02ExecutorWithPermit.executeWithPermit(
//             SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
//             abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData),
//             tokenInPermitData
//         );
//         snapEnd();

//         assertEq(tokenIn.balanceOf(swapper), 0);
//         assertEq(tokenIn.balanceOf(address(swapRouter02ExecutorWithPermit)), 0);
//         assertEq(tokenOut.balanceOf(swapper), ONE / 2);
//         assertEq(tokenOut.balanceOf(address(swapRouter02ExecutorWithPermit)), ONE / 2);
//     }

//     function testExecuteWithPermitAlreadyApproved() public {
//         DutchOrder memory order = DutchOrder({
//             info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
//             decayStartTime: block.timestamp - 100,
//             decayEndTime: block.timestamp + 100,
//             input: DutchInput(tokenIn, ONE, ONE),
//             outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
//         });

//         tokenIn.mint(swapper, 2 * ONE);
//         tokenOut.mint(address(mockSwapRouter), 2 * ONE);

//         address[] memory tokensToApproveForSwapRouter02 = new address[](1);
//         tokensToApproveForSwapRouter02[0] = address(tokenIn);

//         address[] memory tokensToApproveForReactor = new address[](1);
//         tokensToApproveForReactor[0] = address(tokenOut);

//         bytes[] memory multicallData = new bytes[](1);
//         ExactInputParams memory exactInputParams = ExactInputParams({
//             path: abi.encodePacked(tokenIn, FEE, tokenOut),
//             recipient: address(swapRouter02ExecutorWithPermit),
//             amountIn: ONE,
//             amountOutMinimum: 0
//         });
//         multicallData[0] = abi.encodeWithSelector(ISwapRouter02.exactInput.selector, exactInputParams);

//         swapRouter02ExecutorWithPermit.executeWithPermit(
//             SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
//             abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData),
//             tokenInPermitData
//         );

//         DutchOrder memory order2 = DutchOrder({
//             info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
//                 1234
//                 ),
//             decayStartTime: block.timestamp - 100,
//             decayEndTime: block.timestamp + 100,
//             input: DutchInput(tokenIn, ONE, ONE),
//             outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
//         });

//         tokensToApproveForSwapRouter02 = new address[](0);
//         tokensToApproveForReactor = new address[](0);

//         // after permit, we can now use the standard execute flow
//         snapStart("SwapRouter02ExecutorWithPermitExecuteAlreadyApproved");
//         swapRouter02ExecutorWithPermit.execute(
//             SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey, address(permit2), order2)),
//             abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
//         );
//         snapEnd();

//         assertEq(tokenIn.balanceOf(swapper), 0);
//         assertEq(tokenIn.balanceOf(address(swapRouter02ExecutorWithPermit)), 0);
//         assertEq(tokenOut.balanceOf(swapper), ONE);
//         assertEq(tokenOut.balanceOf(address(swapRouter02ExecutorWithPermit)), ONE);
//     }

//     // Requested output = 2 & input = 1. SwapRouter swaps at 1 to 1 rate, so there will
//     // there will be an overflow error when reactor tries to transfer 2 outputToken out of fill contract.
//     function testExecuteWithPermitInsufficientOutput() public {
//         DutchOrder memory order = DutchOrder({
//             info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
//             decayStartTime: block.timestamp - 100,
//             decayEndTime: block.timestamp + 100,
//             input: DutchInput(tokenIn, ONE, ONE),
//             // The output will resolve to 2
//             outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE * 2, ONE * 2, address(swapper))
//         });

//         tokenIn.mint(swapper, ONE);
//         tokenOut.mint(address(mockSwapRouter), ONE * 2);

//         address[] memory tokensToApproveForSwapRouter02 = new address[](1);
//         tokensToApproveForSwapRouter02[0] = address(tokenIn);

//         address[] memory tokensToApproveForReactor = new address[](1);
//         tokensToApproveForReactor[0] = address(tokenOut);

//         bytes[] memory multicallData = new bytes[](1);
//         ExactInputParams memory exactInputParams = ExactInputParams({
//             path: abi.encodePacked(tokenIn, FEE, tokenOut),
//             recipient: address(swapRouter02ExecutorWithPermit),
//             amountIn: ONE,
//             amountOutMinimum: 0
//         });
//         multicallData[0] = abi.encodeWithSelector(ISwapRouter02.exactInput.selector, exactInputParams);

//         vm.expectRevert("TRANSFER_FROM_FAILED");
//         swapRouter02ExecutorWithPermit.executeWithPermit(
//             SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
//             abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData),
//             tokenInPermitData
//         );
//     }

//     // Two orders, first one has input = 1 and outputs = [1]. Second one has input = 3
//     // and outputs = [2]. Mint swapper 10 input and mint mockSwapRouter 10 output. After
//     // the execution, swapper should have 6 input / 3 output, mockSwapRouter should have
//     // 4 input / 6 output, and swapRouter02ExecutorWithPermit should have 0 input / 1 output.
//     function testExecuteWithPermitBatch() public {
//         uint256 inputAmount = 10 ** 18;
//         uint256 outputAmount = inputAmount;

//         tokenIn.mint(address(swapper), inputAmount * 10);
//         tokenOut.mint(address(mockSwapRouter), outputAmount * 10);
//         tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

//         SignedOrder[] memory signedOrders = new SignedOrder[](2);
//         DutchOrder memory order1 = DutchOrder({
//             info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
//             decayStartTime: block.timestamp,
//             decayEndTime: block.timestamp + 100,
//             input: DutchInput(tokenIn, inputAmount, inputAmount),
//             outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
//         });
//         bytes memory sig1 = signOrder(swapperPrivateKey, address(permit2), order1);
//         signedOrders[0] = SignedOrder(abi.encode(order1), sig1);

//         DutchOrder memory order2 = DutchOrder({
//             info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
//                 1
//                 ),
//             decayStartTime: block.timestamp,
//             decayEndTime: block.timestamp + 100,
//             input: DutchInput(tokenIn, inputAmount * 3, inputAmount * 3),
//             outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, swapper)
//         });
//         bytes memory sig2 = signOrder(swapperPrivateKey, address(permit2), order2);
//         signedOrders[1] = SignedOrder(abi.encode(order2), sig2);

//         address[] memory tokensToApproveForSwapRouter02 = new address[](1);
//         tokensToApproveForSwapRouter02[0] = address(tokenIn);

//         address[] memory tokensToApproveForReactor = new address[](1);
//         tokensToApproveForReactor[0] = address(tokenOut);

//         bytes[] memory multicallData = new bytes[](1);
//         ExactInputParams memory exactInputParams = ExactInputParams({
//             path: abi.encodePacked(tokenIn, FEE, tokenOut),
//             recipient: address(swapRouter02ExecutorWithPermit),
//             amountIn: inputAmount * 4,
//             amountOutMinimum: 0
//         });
//         multicallData[0] = abi.encodeWithSelector(ISwapRouter02.exactInput.selector, exactInputParams);

//         bytes[] memory permitData = new bytes[](1);
//         permitData[0] = tokenInPermitData;

//         swapRouter02ExecutorWithPermit.executeBatchWithPermit(
//             signedOrders,
//             abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData),
//             permitData
//         );
//         assertEq(tokenOut.balanceOf(swapper), 3 ether);
//         assertEq(tokenIn.balanceOf(swapper), 6 ether);
//         assertEq(tokenOut.balanceOf(address(mockSwapRouter)), 6 ether);
//         assertEq(tokenIn.balanceOf(address(mockSwapRouter)), 4 ether);
//         assertEq(tokenOut.balanceOf(address(swapRouter02ExecutorWithPermit)), 10 ** 18);
//         assertEq(tokenIn.balanceOf(address(swapRouter02ExecutorWithPermit)), 0);
//     }

//     function testNotWhitelistedCaller() public {
//         DutchOrder memory order = DutchOrder({
//             info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
//             decayStartTime: block.timestamp - 100,
//             decayEndTime: block.timestamp + 100,
//             input: DutchInput(tokenIn, ONE, ONE),
//             outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
//         });

//         tokenIn.mint(swapper, ONE);
//         tokenOut.mint(address(mockSwapRouter), ONE);

//         address[] memory tokensToApproveForSwapRouter02 = new address[](1);
//         tokensToApproveForSwapRouter02[0] = address(tokenIn);

//         bytes[] memory multicallData = new bytes[](1);
//         ExactInputParams memory exactInputParams = ExactInputParams({
//             path: abi.encodePacked(tokenIn, FEE, tokenOut),
//             recipient: address(swapRouter02ExecutorWithPermit),
//             amountIn: ONE,
//             amountOutMinimum: 0
//         });
//         multicallData[0] = abi.encodeWithSelector(ISwapRouter02.exactInput.selector, exactInputParams);

//         vm.prank(address(0xbeef));
//         vm.expectRevert(SwapRouter02Executor.CallerNotWhitelisted.selector);
//         swapRouter02ExecutorWithPermit.executeWithPermit(
//             SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
//             abi.encode(tokensToApproveForSwapRouter02, multicallData),
//             tokenInPermitData
//         );
//     }

//     // Very similar to `testReactorCallback`, but do not vm.prank the reactor when calling `reactorCallback`, so reverts
//     function testMsgSenderNotReactor() public {
//         OutputToken[] memory outputs = new OutputToken[](1);
//         outputs[0].token = address(tokenOut);
//         outputs[0].amount = ONE;
//         address[] memory tokensToApproveForSwapRouter02 = new address[](1);
//         tokensToApproveForSwapRouter02[0] = address(tokenIn);

//         bytes[] memory multicallData = new bytes[](1);
//         ExactInputParams memory exactInputParams = ExactInputParams({
//             path: abi.encodePacked(tokenIn, FEE, tokenOut),
//             recipient: address(swapRouter02ExecutorWithPermit),
//             amountIn: ONE,
//             amountOutMinimum: 0
//         });
//         multicallData[0] = abi.encodeWithSelector(ISwapRouter02.exactInput.selector, exactInputParams);
//         bytes memory callbackData = abi.encode(tokensToApproveForSwapRouter02, multicallData);

//         ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
//         bytes memory sig = hex"1234";
//         resolvedOrders[0] = ResolvedOrder(
//             OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
//             InputToken(tokenIn, ONE, ONE),
//             outputs,
//             sig,
//             keccak256(abi.encode(1))
//         );
//         tokenIn.mint(address(swapRouter02ExecutorWithPermit), ONE);
//         tokenOut.mint(address(mockSwapRouter), ONE);
//         vm.expectRevert(SwapRouter02Executor.MsgSenderNotReactor.selector);
//         swapRouter02ExecutorWithPermit.reactorCallback(resolvedOrders, callbackData);
//     }

//     function testUnwrapWETH() public {
//         vm.deal(address(weth), 1 ether);
//         deal(address(weth), address(swapRouter02ExecutorWithPermit), ONE);
//         uint256 balanceBefore = address(this).balance;
//         swapRouter02ExecutorWithPermit.unwrapWETH(address(this));
//         uint256 balanceAfter = address(this).balance;
//         assertEq(balanceAfter - balanceBefore, 1 ether);
//     }

//     function testUnwrapWETHNotOwner() public {
//         vm.expectRevert("UNAUTHORIZED");
//         vm.prank(address(0xbeef));
//         swapRouter02ExecutorWithPermit.unwrapWETH(address(this));
//     }

//     function testWithdrawETH() public {
//         vm.deal(address(swapRouter02ExecutorWithPermit), 1 ether);
//         uint256 balanceBefore = address(this).balance;
//         swapRouter02ExecutorWithPermit.withdrawETH(address(this));
//         uint256 balanceAfter = address(this).balance;
//         assertEq(balanceAfter - balanceBefore, 1 ether);
//     }

//     function testWithdrawETHNotOwner() public {
//         vm.expectRevert("UNAUTHORIZED");
//         vm.prank(address(0xbeef));
//         swapRouter02ExecutorWithPermit.withdrawETH(address(this));
//     }
// }

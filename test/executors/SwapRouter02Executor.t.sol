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
import {ISwapRouter02, ExactInputSingleParams} from "../../src/external/ISwapRouter02.sol";

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
    bytes32 constant TRANSFER_EVENT_SIG = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    bytes32 constant APPROVAL_EVENT_SIG = 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;
    bytes32 constant FILL_EVENT_SIG = 0x78ad7ec0e9f89e74012afa58738b6b661c024cb0fd185ee2f616c0a28924bd66;

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
        ExactInputSingleParams memory exactInputSingleParams =
            ExactInputSingleParams(address(tokenIn), address(tokenOut), 500, address(swapRouter02Executor), ONE, ONE, 0);
        multicallData[0] = abi.encodeWithSelector(ISwapRouter02.exactInputSingle.selector, exactInputSingleParams);
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
}

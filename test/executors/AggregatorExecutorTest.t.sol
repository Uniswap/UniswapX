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
import {WETH} from "solmate/src/tokens/WETH.sol";
import {MockSwapRouter} from "../util/mock/MockSwapRouter.sol";
import {MockOneInchAggregator} from "../util/mock/MockOneInchAggregator.sol";
import {OutputToken, InputToken, OrderInfo, ResolvedOrder, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ISwapRouter02} from "../../src/external/ISwapRouter02.sol";
import {IUniV3SwapRouter} from "../../src/external/IUniV3SwapRouter.sol";
import {AggregatorExecutor} from "../../src/sample-executors/AggregatorExecutor.sol";
import {FundMaintenance} from "../../src/sample-executors/FundMaintenance.sol";
import {ETH_ADDRESS} from "../../src/base/ReactorStructs.sol";

// This set of tests will use a mock aggregator to mock the call to the 1inch aggreagtor.
// We also set up a mock swap router to simulate the Uniswap swap router for the final eth swap call out of the executor.
contract AggregatorExecutorTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;

    uint256 takerPrivateKey;
    uint256 makerPrivateKey;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    WETH weth;
    address taker;
    address maker;
    AggregatorExecutor executor;
    MockSwapRouter mockSwapRouter;
    MockOneInchAggregator mockAggregator;
    DutchLimitOrderReactor reactor;
    ISignatureTransfer permit2;

    uint256 constant ONE = 10 ** 18;
    // Represents a 0.3% fee, but setting this doesn't matter
    uint24 constant FEE = 3000;
    address constant PROTOCOL_FEE_RECIPIENT = address(80085);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    address constant ONE_INCH_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

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
        mockAggregator = new MockOneInchAggregator();
        permit2 = ISignatureTransfer(deployPermit2());
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        executor =
        new AggregatorExecutor(address(this), address(reactor), address(this), address(mockAggregator), address(mockSwapRouter));

        // Do appropriate max approvals
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);
    }

    function testReactorCallback() public {
        ResolvedOrder[] memory resolvedOrders;
        bytes memory fillData;
        (resolvedOrders, fillData) = getSimpleOrderAndFillData(address(tokenIn), address(tokenOut));

        tokenIn.mint(address(executor), ONE);
        tokenOut.mint(address(mockAggregator), ONE);

        vm.prank(address(reactor));
        executor.reactorCallback(resolvedOrders, address(this), fillData);

        assertEq(tokenIn.balanceOf(address(mockAggregator)), ONE);
        assertEq(tokenOut.balanceOf(address(executor)), ONE);
    }

    function testReactorCallbackWithEthOutput() public {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = ETH_ADDRESS;
        outputs[0].amount = ONE;

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            InputToken(address(tokenIn), ONE, ONE),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );

        address[] memory tokensToApproveForAggregator = new address[](1);
        tokensToApproveForAggregator[0] = address(tokenIn);

        address[] memory tokensToApproveForReactor; // eth doesnt require pulling from reactor

        uint256[] memory pools = new uint256[](1);
        pools[0] = uint256(uint160(ONE_INCH_ETH_ADDRESS));

        bytes memory swapData = abi.encodeWithSelector(MockOneInchAggregator.unoswap.selector, tokenIn, ONE, 0, pools);
        bytes memory fillData = abi.encode(tokensToApproveForAggregator, tokensToApproveForReactor, swapData);

        // mock maker send input token to executor
        tokenIn.mint(address(executor), ONE);

        // mock liquidity in aggregator
        vm.deal(address(mockAggregator), ONE);

        vm.prank(address(reactor));
        executor.reactorCallback(resolvedOrders, address(this), fillData);

        assertEq(tokenIn.balanceOf(address(mockAggregator)), ONE);
        // reactor was sent eth from executor
        assertEq(address(reactor).balance, ONE);
    }

    function testExecute() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(maker))
        });

        tokenIn.mint(maker, ONE);
        tokenOut.mint(address(mockAggregator), ONE);

        address[] memory tokensToApproveForAggregator = new address[](1);
        tokensToApproveForAggregator[0] = address(tokenIn);
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(tokenOut);

        uint256[] memory pools = new uint256[](1);
        pools[0] = uint256(uint160(address(tokenOut)));

        bytes memory swapData =
            abi.encodeWithSelector(MockOneInchAggregator.unoswap.selector, address(tokenIn), ONE, 0, pools);
        bytes memory fillData = abi.encode(tokensToApproveForAggregator, tokensToApproveForReactor, swapData);

        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(executor),
            fillData
        );

        assertEq(tokenIn.balanceOf(maker), 0);
        assertEq(tokenIn.balanceOf(address(executor)), 0);
        assertEq(tokenOut.balanceOf(maker), ONE / 2);
        assertEq(tokenOut.balanceOf(address(executor)), ONE / 2);
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
        tokenOut.mint(address(mockAggregator), ONE * 2);

        address[] memory tokensToApproveForAggregator = new address[](1);
        tokensToApproveForAggregator[0] = address(tokenIn);
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(tokenOut);

        uint256[] memory pools = new uint256[](1);
        pools[0] = uint256(uint160(address(tokenOut)));

        bytes memory swapData =
            abi.encodeWithSelector(MockOneInchAggregator.unoswap.selector, address(tokenIn), ONE, 0, pools);

        vm.expectRevert(AggregatorExecutor.InsufficientTokenBalance.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(executor),
            abi.encode(tokensToApproveForAggregator, tokensToApproveForReactor, swapData)
        );
    }

    function testFundMaintenanceSwapMulticall() public {
        tokenOut.mint(address(executor), ONE);

        assertEq(tokenOut.balanceOf(address(executor)), ONE);

        bytes[] memory data = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenOut, FEE, address(weth)),
            recipient: address(executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        data[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenOut);

        vm.deal(address(weth), 1 ether);
        deal(address(weth), address(mockSwapRouter), ONE);

        executor.swapMulticall(tokensToApproveForSwapRouter02, data);

        assertEq(weth.balanceOf(address(executor)), ONE);
        assertEq(tokenOut.balanceOf(address(mockSwapRouter)), ONE);
    }

    function testGeneralMulticallSwapThenUnwrap() public {
        tokenOut.mint(address(executor), ONE);
        assertEq(tokenOut.balanceOf(address(executor)), ONE);

        bytes[] memory swapData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenOut, FEE, address(weth)),
            recipient: address(executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        swapData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenOut);

        bytes memory swapMutlicallData =
            abi.encodeWithSelector(FundMaintenance.swapMulticall.selector, tokensToApproveForSwapRouter02, swapData);

        bytes memory unwrapData = abi.encodeWithSelector(FundMaintenance.unwrapWETH.selector, maker);
        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = swapMutlicallData;
        multicallData[1] = unwrapData;

        vm.deal(address(weth), 1 ether);
        deal(address(weth), address(mockSwapRouter), ONE);

        executor.multicall(multicallData);

        assertEq(weth.balanceOf(address(executor)), 0);
        assertEq(maker.balance, ONE);
        assertEq(tokenOut.balanceOf(address(mockSwapRouter)), ONE);
    }

    function testUnwrapWETH() public {
        vm.deal(address(weth), 1 ether);
        deal(address(weth), address(executor), ONE);
        uint256 balanceBefore = address(this).balance;
        executor.unwrapWETH(address(this));
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function testUnwrapWETHNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xbeef));
        executor.unwrapWETH(address(this));
    }

    function testUnwrapWETHInsuffucientBalance() public {
        vm.expectRevert(FundMaintenance.InsufficientWETHBalance.selector);
        executor.unwrapWETH(address(this));
    }

    function testWithdrawETH() public {
        vm.deal(address(executor), 1 ether);
        uint256 balanceBefore = address(this).balance;
        executor.withdrawETH(address(this));
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function testWithdrawETHNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xbeef));
        executor.withdrawETH(address(this));
    }

    // Builds a ResolvedOrder for:
    // (tokenIn, ONE) -> (tokenOut, ONE)
    // Builds calldata specific for the swap from tokenIn to tokenOut
    function getSimpleOrderAndFillData(address tokenIn, address tokenOut)
        private
        view
        returns (ResolvedOrder[] memory resolvedOrders, bytes memory fillData)
    {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = tokenOut;
        outputs[0].amount = ONE;

        resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            InputToken(tokenIn, ONE, ONE),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );

        address[] memory tokensToApproveForAggregator = new address[](1);
        tokensToApproveForAggregator[0] = tokenIn;

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = tokenOut;

        uint256[] memory pools = new uint256[](1);
        pools[0] = uint256(uint160(tokenOut));

        bytes memory swapData = abi.encodeWithSelector(MockOneInchAggregator.unoswap.selector, tokenIn, ONE, 0, pools);
        fillData = abi.encode(tokensToApproveForAggregator, tokensToApproveForReactor, swapData);
    }
}

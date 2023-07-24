// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SwapRouter02Executor} from "../../src/sample-executors/SwapRouter02Executor.sol";
import {InputToken, OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {DutchOrderReactor, DutchOrder, DutchInput, DutchOutput} from "../../src/reactors/DutchOrderReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ISwapRouter02, ExactInputSingleParams} from "../../src/external/ISwapRouter02.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

// This set of tests will use a mainnet fork to test integration.
contract SwapRouter02IntegrationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using SafeTransferLib for ERC20;

    ERC20 constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    ERC20 constant USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ISwapRouter02 constant SWAPROUTER02 = ISwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    address constant WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    uint256 constant ONE = 1000000000000000000;

    address swapper;
    address swapper2;
    uint256 swapperPrivateKey;
    uint256 swapper2PrivateKey;
    address filler;
    SwapRouter02Executor swapRouter02Executor;
    DutchOrderReactor dloReactor;

    function setUp() public {
        swapperPrivateKey = 0xbabe;
        swapper = vm.addr(swapperPrivateKey);
        swapper2PrivateKey = 0xbeef;
        swapper2 = vm.addr(swapper2PrivateKey);
        filler = makeAddr("filler");
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 16586505);
        dloReactor = new DutchOrderReactor(PERMIT2, address(0));
        swapRouter02Executor = new SwapRouter02Executor(address(this), dloReactor, address(this), SWAPROUTER02);

        // Swapper max approves permit post
        vm.prank(swapper);
        WETH.approve(address(PERMIT2), type(uint256).max);

        // Transfer 3 WETH to swapper
        vm.prank(WHALE);
        WETH.transfer(swapper, 3 * ONE);
    }

    // Swapper creates below 2 orders, and both are filled via SwapRouter02Executor via Uniswap V3.
    // Order 1: input = 2 WETH, output = 3000 DAI
    // Order 2: input = 1 WETH, output = 1600 DAI
    // I chose to test using 2 orders to test that the 2nd execute call will not have to pass in
    // `tokensToApproveForSwapRouter02`
    // There will be 288797467469336654155 wei of DAI in SwapRouter02Executor after the 1st order is filled.
    // There will be 332868886072663242927 wei of DAI in SwapRouter02Executor after the 2nd order is filled.
    function testSwapWethToDaiViaV3() public {
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 3000 * ONE, 3000 * ONE, address(swapper))
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 1600 * ONE, 1600 * ONE, address(swapper))
        });
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);
        bytes[] memory multicallData1 = new bytes[](1);
        bytes[] memory multicallData2 = new bytes[](1);

        ExactInputSingleParams memory params1 = ExactInputSingleParams(
            address(WETH), address(DAI), 500, address(swapRouter02Executor), 2 * ONE, 3000 * ONE, 0
        );
        multicallData1[0] = abi.encodeWithSelector(ISwapRouter02.exactInputSingle.selector, params1);
        swapRouter02Executor.execute(
            SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey, address(PERMIT2), order1)),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData1)
        );
        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(DAI.balanceOf(swapper), 3000 * ONE);
        assertEq(DAI.balanceOf(address(swapRouter02Executor)), 288797467469336654155);

        ExactInputSingleParams memory params2 =
            ExactInputSingleParams(address(WETH), address(DAI), 500, address(swapRouter02Executor), ONE, 1600 * ONE, 0);
        multicallData2[0] = abi.encodeWithSelector(ISwapRouter02.exactInputSingle.selector, params2);
        swapRouter02Executor.execute(
            SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey, address(PERMIT2), order2)),
            abi.encode(new address[](0), new address[](0), multicallData2)
        );
        assertEq(WETH.balanceOf(swapper), 0);
        assertEq(DAI.balanceOf(swapper), 4600 * ONE);
        assertEq(DAI.balanceOf(address(swapRouter02Executor)), 332868886072663242927);
    }

    // Swapper creates order of input = 2 WETH and output = 3000 DAI. Trade via Uniswap V2.
    // There will be 275438458971501955836 wei of DAI in SwapRouter02Executor after.
    function testSwapWethToDaiViaV2() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 3000 * ONE, 3000 * ONE, address(swapper))
        });

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);
        bytes[] memory multicallData = new bytes[](1);
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(DAI);
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 2 * ONE, 3000 * ONE, path, address(swapRouter02Executor)
        );
        swapRouter02Executor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order)),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
        );
        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(DAI.balanceOf(swapper), 3000 * ONE);
        assertEq(DAI.balanceOf(address(swapRouter02Executor)), 275438458971501955836);
    }

    // Swapper creates order of input = 2 WETH and output = 3000 USDT. Trade via Uniswap V2.
    // There will be 275438458971501955836 wei of USDT in SwapRouter02Executor after.
    function testSwapWethToUsdtViaV2() public {
        uint256 output = 300 * 10 ** 6;
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(address(USDT), output, output, address(swapper))
        });

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(USDT);
        bytes[] memory multicallData = new bytes[](1);
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDT);
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 2 * ONE, output, path, address(swapRouter02Executor)
        );
        swapRouter02Executor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order)),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
        );
        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(USDT.balanceOf(swapper), output);
    }

    // Swapper creates order of input = 2 WETH and output = 3000 USDT. Trade via Uniswap V2.
    // There will be 275438458971501955836 wei of USDT in SwapRouter02Executor after.
    function testSwapUsdtToWethViaV2() public {
        uint256 input = 2000 * 10 ** 6;
        uint256 output = 1 ether;

        // Swapper max approves permit post
        vm.prank(swapper);
        USDT.safeApprove(address(PERMIT2), type(uint256).max);
        deal(address(USDT), address(swapper), input);
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(USDT, input, input),
            outputs: OutputsBuilder.singleDutch(address(WETH), output, output, address(swapper))
        });

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(USDT);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(WETH);
        bytes[] memory multicallData = new bytes[](1);
        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = address(WETH);
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, input, output, path, address(swapRouter02Executor)
        );
        swapRouter02Executor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order)),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
        );
        assertEq(USDT.balanceOf(swapper), 0);
        assertEq(WETH.balanceOf(swapper), 4 * ONE);
    }

    // Exact same test as testSwapWethToDaiViaV2, but the order requests 4000 DAI output, which is too much for
    // given 2 WETH input. Should revert with "Too little received".
    function testSwapWethToDaiViaV2InsufficientOutput() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 4000 * ONE, 4000 * ONE, address(swapper))
        });

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);
        bytes[] memory multicallData = new bytes[](1);
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(DAI);
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 2 * ONE, 4000 * ONE, path, address(swapRouter02Executor)
        );
        vm.expectRevert("Too little received");
        swapRouter02Executor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order)),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
        );
    }

    // There is 1000 DAI and 1000 UNI in swapRouter02Executor. Test that we can convert it to ETH
    // successfully.
    function testConvertERC20sToEth() public {
        // Transfer 1000 DAI and 1000 UNI to swapRouter02Executor
        vm.prank(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
        DAI.transfer(address(swapRouter02Executor), 1000 * ONE);
        vm.prank(0x47173B170C64d16393a52e6C480b3Ad8c302ba1e);
        UNI.transfer(address(swapRouter02Executor), 1000 * ONE);

        ERC20[] memory tokensToApproveForSwapRouter02 = new ERC20[](2);
        tokensToApproveForSwapRouter02[0] = DAI;
        tokensToApproveForSwapRouter02[1] = UNI;

        bytes[] memory multicallData = new bytes[](3);
        address[] memory daiToEthPath = new address[](2);
        daiToEthPath[0] = address(DAI);
        daiToEthPath[1] = address(WETH);
        address[] memory uniToEthPath = new address[](2);
        uniToEthPath[0] = address(UNI);
        uniToEthPath[1] = address(WETH);
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 1000 * ONE, 0, daiToEthPath, address(2)
        );
        multicallData[1] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 1000 * ONE, 0, uniToEthPath, address(2)
        );
        multicallData[2] = abi.encodeWithSelector(ISwapRouter02.unwrapWETH9.selector, 0, address(swapRouter02Executor));
        swapRouter02Executor.multicall(tokensToApproveForSwapRouter02, multicallData);
        assertEq(address(swapRouter02Executor).balance, 4667228409436457308);
    }

    function testMulticallOnlyOwner() public {
        vm.prank(address(0xbeef));
        vm.expectRevert("UNAUTHORIZED");
        swapRouter02Executor.multicall(new ERC20[](0), new bytes[](0));
    }

    // Swapper's order has input = 2000 DAI and output = 1 ETH. 213039886077866602 excess wei of ETH will remain in
    // swapRouter02Executor.
    function testSwapDaiToETHViaV2() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(DAI, 2000 * ONE, 2000 * ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE, ONE, address(swapper))
        });

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(DAI);

        address[] memory tokensToApproveForReactor = new address[](0);
        bytes[] memory multicallData = new bytes[](2);
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);
        multicallData[0] =
            abi.encodeWithSelector(ISwapRouter02.swapExactTokensForTokens.selector, 2000 * ONE, ONE, path, SWAPROUTER02);
        multicallData[1] = abi.encodeWithSelector(ISwapRouter02.unwrapWETH9.selector, 0, address(swapRouter02Executor));

        // Swapper max approves permit post
        vm.prank(swapper);
        DAI.approve(address(PERMIT2), type(uint256).max);

        // Transfer 2000 DAI to swapper
        vm.prank(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        DAI.transfer(swapper, 2000 * ONE);

        swapRouter02Executor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order)),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
        );
        assertEq(DAI.balanceOf(swapper), 0);
        assertEq(DAI.balanceOf(address(swapRouter02Executor)), 0);
        assertEq(swapper.balance, 1000000000000000000);
        assertEq(address(swapRouter02Executor).balance, 213039886077866602);
    }

    // Swapper's order has input = 2000 DAI and output = 2 ETH. This is not enough DAI, so revert with "Too little received".
    function testSwapDaiToEthViaV2ButInsufficientDai() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(DAI, 2000 * ONE, 2000 * ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE * 2, ONE * 2, address(swapper))
        });

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(DAI);

        address[] memory tokensToApproveForReactor = new address[](0);
        bytes[] memory multicallData = new bytes[](2);
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 2000 * ONE, 2 * ONE, path, SWAPROUTER02
        );
        multicallData[1] = abi.encodeWithSelector(ISwapRouter02.unwrapWETH9.selector, 0, address(swapRouter02Executor));

        // Maker max approves permit post
        vm.prank(swapper);
        DAI.approve(address(PERMIT2), type(uint256).max);

        // Transfer 2000 DAI to swapper
        vm.prank(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        DAI.transfer(swapper, 2000 * ONE);

        vm.expectRevert("Too little received");
        swapRouter02Executor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order)),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
        );
    }

    // Test a batch execute, dai -> ETH via v2. Order 1: input = 2000 DAI, output = 1 ETH. Order 2: input = 1000 DAI,
    // output = 0.5 ETH.
    function testBatchSwapDaiToEthViaV2() public {
        vm.prank(swapper);
        DAI.approve(address(PERMIT2), type(uint256).max);
        vm.prank(swapper2);
        DAI.approve(address(PERMIT2), type(uint256).max);

        vm.prank(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        DAI.transfer(swapper, 2000 * ONE);
        vm.prank(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        DAI.transfer(swapper2, 1000 * ONE);

        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(DAI, ONE * 2000, ONE * 2000),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE, ONE, swapper)
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(DAI, ONE * 1000, ONE * 1000),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE / 2, ONE / 2, swapper2)
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey, address(PERMIT2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapper2PrivateKey, address(PERMIT2), order2));

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(DAI);

        address[] memory tokensToApproveForReactor = new address[](0);
        bytes[] memory multicallData = new bytes[](2);
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 3000 * ONE, ONE * 3 / 2, path, SWAPROUTER02
        );
        multicallData[1] = abi.encodeWithSelector(ISwapRouter02.unwrapWETH9.selector, 0, address(swapRouter02Executor));

        swapRouter02Executor.executeBatch(
            signedOrders, abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
        );
        assertEq(swapper.balance, ONE);
        assertEq(swapper2.balance, ONE / 2);
        assertEq(address(swapRouter02Executor).balance, 319317550497372609);
    }

    // There is 10 WETH swapRouter02Executor. Test that we can convert it to ETH
    // and withdraw successfully.
    function testUnwrapWETH() public {
        assertEq(filler.balance, 0);

        // Transfer 10 WETH to swapRouter02Executor
        vm.prank(WHALE);
        WETH.transfer(address(swapRouter02Executor), 10 * ONE);

        // unwrap WETH and withdraw ETH to bot wallet
        swapRouter02Executor.unwrapWETH(filler);
        assertEq(filler.balance, 10 * ONE);
    }
}

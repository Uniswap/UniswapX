// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SwapRouter02Executor} from "../../src/sample-executors/SwapRouter02Executor.sol";
import {InputToken, OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchInput} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ISwapRouter02, ExactInputSingleParams} from "../../src/external/ISwapRouter02.sol";

// This set of tests will use a mainnet fork to test integration.
contract SwapRouter02IntegrationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant SWAPROUTER02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint256 constant ONE = 1000000000000000000;

    address maker;
    uint256 makerPrivateKey;
    SwapRouter02Executor swapRouter02Executor;
    DutchLimitOrderReactor dloReactor;

    function setUp() public {
        makerPrivateKey = 0xbabe;
        maker = vm.addr(makerPrivateKey);
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 16586505);
        dloReactor = new DutchLimitOrderReactor(PERMIT2, 100, address(0));
        swapRouter02Executor =
        new SwapRouter02Executor(address(this), address(dloReactor), address(this), 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

        // Maker max approves permit post
        vm.prank(maker);
        ERC20(WETH).approve(PERMIT2, type(uint256).max);

        // Transfer 3 WETH to maker
        vm.prank(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        ERC20(WETH).transfer(maker, 3 * ONE);
    }

    // Maker creates below 2 orders, and both are filled via SwapRouter02Executor via Uniswap V3.
    // Order 1: input = 2 WETH, output = 3000 DAI
    // Order 2: input = 1 WETH, output = 1600 DAI
    // I chose to test using 2 orders to test that the 2nd execute call will not have to pass in
    // `tokensToApproveForSwapRouter02` nor `tokensToApproveForReactor`.
    // There will be 288797467469336654155 wei of DAI in SwapRouter02Executor after the 1st order is filled.
    // There will be 332868886072663242927 wei of DAI in SwapRouter02Executor after the 2nd order is filled.
    function testSwapWethToDaiViaV3() public {
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(WETH), 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 3000 * ONE, 3000 * ONE, address(maker))
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withNonce(1),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(WETH), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 1600 * ONE, 1600 * ONE, address(maker))
        });
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = WETH;
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = DAI;
        bytes[] memory multicallData1 = new bytes[](1);
        bytes[] memory multicallData2 = new bytes[](1);

        ExactInputSingleParams memory params1 =
            ExactInputSingleParams(WETH, DAI, 500, address(swapRouter02Executor), 2 * ONE, 3000 * ONE, 0);
        multicallData1[0] = abi.encodeWithSelector(ISwapRouter02.exactInputSingle.selector, params1);
        dloReactor.execute(
            SignedOrder(abi.encode(order1), signOrder(makerPrivateKey, PERMIT2, order1)),
            address(swapRouter02Executor),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData1)
        );
        assertEq(ERC20(WETH).balanceOf(maker), ONE);
        assertEq(ERC20(DAI).balanceOf(maker), 3000 * ONE);
        assertEq(ERC20(DAI).balanceOf(address(swapRouter02Executor)), 288797467469336654155);

        ExactInputSingleParams memory params2 =
            ExactInputSingleParams(WETH, DAI, 500, address(swapRouter02Executor), ONE, 1600 * ONE, 0);
        multicallData2[0] = abi.encodeWithSelector(ISwapRouter02.exactInputSingle.selector, params2);
        dloReactor.execute(
            SignedOrder(abi.encode(order2), signOrder(makerPrivateKey, PERMIT2, order2)),
            address(swapRouter02Executor),
            abi.encode(new address[](0), new address[](0), multicallData2)
        );
        assertEq(ERC20(WETH).balanceOf(maker), 0);
        assertEq(ERC20(DAI).balanceOf(maker), 4600 * ONE);
        assertEq(ERC20(DAI).balanceOf(address(swapRouter02Executor)), 332868886072663242927);
    }

    // Maker creates order of input = 2 WETH and output = 3000 DAI. Trade via Uniswap V2.
    // There will be 275438458971501955836 wei of DAI in SwapRouter02Executor after.
    function testSwapWethToDaiViaV2() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(WETH), 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 3000 * ONE, 3000 * ONE, address(maker))
        });

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = WETH;
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = DAI;
        bytes[] memory multicallData = new bytes[](1);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 2 * ONE, 3000 * ONE, path, address(swapRouter02Executor)
        );
        dloReactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, PERMIT2, order)),
            address(swapRouter02Executor),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
        );
        assertEq(ERC20(WETH).balanceOf(maker), ONE);
        assertEq(ERC20(DAI).balanceOf(maker), 3000 * ONE);
        assertEq(ERC20(DAI).balanceOf(address(swapRouter02Executor)), 275438458971501955836);
    }

    // Exact same test as testSwapWethToDaiViaV2, but the order requests 4000 DAI output, which is too much for
    // given 2 WETH input. Should revert with "Too little received".
    function testSwapWethToDaiViaV2InsufficientOutput() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(WETH), 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 4000 * ONE, 4000 * ONE, address(maker))
        });

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = WETH;
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = DAI;
        bytes[] memory multicallData = new bytes[](1);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 2 * ONE, 4000 * ONE, path, address(swapRouter02Executor)
        );
        vm.expectRevert("Too little received");
        dloReactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, PERMIT2, order)),
            address(swapRouter02Executor),
            abi.encode(tokensToApproveForSwapRouter02, tokensToApproveForReactor, multicallData)
        );
    }

    // There is 1000 DAI and 1000 UNI in swapRouter02Executor. Test that we can convert it to ETH
    // successfully.
    function testConvertERC20sToEth() public {
        // Transfer 1000 DAI and 1000 UNI to swapRouter02Executor
        vm.prank(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
        ERC20(DAI).transfer(address(swapRouter02Executor), 1000 * ONE);
        vm.prank(0x47173B170C64d16393a52e6C480b3Ad8c302ba1e);
        ERC20(UNI).transfer(address(swapRouter02Executor), 1000 * ONE);

        address[] memory tokensToApproveForSwapRouter02 = new address[](2);
        tokensToApproveForSwapRouter02[0] = DAI;
        tokensToApproveForSwapRouter02[1] = UNI;
        bytes[] memory multicallData = new bytes[](3);
        address[] memory daiToEthPath = new address[](2);
        daiToEthPath[0] = DAI;
        daiToEthPath[1] = WETH;
        address[] memory uniToEthPath = new address[](2);
        uniToEthPath[0] = UNI;
        uniToEthPath[1] = WETH;
        multicallData[0] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 1000 * ONE, 0, daiToEthPath, address(2)
        );
        multicallData[1] = abi.encodeWithSelector(
            ISwapRouter02.swapExactTokensForTokens.selector, 1000 * ONE, 0, uniToEthPath, address(2)
        );
        multicallData[2] = abi.encodeWithSelector(ISwapRouter02.unwrapWETH9.selector, 0);
        swapRouter02Executor.multicall(tokensToApproveForSwapRouter02, multicallData);
        assertEq(address(swapRouter02Executor).balance, 4667228409436457308);
    }

    function testMulticallOnlyOwner() public {
        vm.prank(address(0xbeef));
        vm.expectRevert("UNAUTHORIZED");
        swapRouter02Executor.multicall(new address[](0), new bytes[](0));
    }
}

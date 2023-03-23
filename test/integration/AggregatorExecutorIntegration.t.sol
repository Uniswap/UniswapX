// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {AggregatorExecutor} from "../../src/sample-executors/AggregatorExecutor.sol";
import {InputToken, OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {ETH_ADDRESS} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchInput,
    DutchOutput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ISwapRouter02, ExactInputSingleParams} from "../../src/external/ISwapRouter02.sol";

import "forge-std/console2.sol";

// This set of tests will use a mainnet fork to test integration.
contract SwapRouter02IntegrationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant SWAPROUTER02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant AGGREGATOR = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address constant WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    address constant DAI_WHALE = 0xD831B3353Be1449d7131e92c8948539b1F18b86A;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint256 constant ONE = 1000000000000000000;

    address maker;
    address maker2;
    uint256 makerPrivateKey;
    uint256 maker2PrivateKey;
    address filler;
    uint256 seedAmount;
    AggregatorExecutor executor;
    DutchLimitOrderReactor dloReactor;

    function setUp() public {
        makerPrivateKey = 0xbabe;
        maker = vm.addr(makerPrivateKey);
        maker2PrivateKey = 0xbeef;
        maker2 = vm.addr(maker2PrivateKey);
        filler = makeAddr("filler");
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 16877250);
        dloReactor = new DutchLimitOrderReactor(PERMIT2, 100, address(0));
        executor = new AggregatorExecutor(address(this), address(dloReactor), address(this), AGGREGATOR, SWAPROUTER02);

        // Maker max approves permit post
        vm.prank(maker);
        ERC20(WETH).approve(PERMIT2, type(uint256).max);

        // Transfer 3 WETH to maker
        seedAmount = 3 * ONE;
        vm.prank(WHALE);
        ERC20(WETH).transfer(maker, 3 * ONE);
    }

    function testSwapWethToDaiViaAggregator() public {
        uint256 order1InputAmount = 2 * ONE;
        uint256 order1OutputAmount = 3000 * ONE;

        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(WETH), order1InputAmount, order1InputAmount),
            outputs: OutputsBuilder.singleDutch(address(DAI), order1OutputAmount, order1OutputAmount, address(maker))
        });

        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withNonce(1),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(WETH), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 1600 * ONE, 1600 * ONE, address(maker))
        });

        address[] memory tokensToApproveForAggregator = new address[](1);
        tokensToApproveForAggregator[0] = WETH;

        // swap data from 1inch api
        bytes memory swapData1 =
            hex"e449022e0000000000000000000000000000000000000000000000001bc16d674ec800000000000000000000000000000000000000000000000000c33414f39d79c2fa850000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000060594a405d53811d3bc4766596efd80fd545a270cfee7c08";

        dloReactor.execute(
            SignedOrder(abi.encode(order1), signOrder(makerPrivateKey, PERMIT2, order1)),
            address(executor),
            abi.encode(tokensToApproveForAggregator, swapData1)
        );

        // the amount of the output token remaining in the executor
        uint256 excessOutputAmount = 649024359659405361033;
        uint256 excessInputAmount = seedAmount - order1InputAmount;
        assertEq(ERC20(WETH).balanceOf(maker), excessInputAmount);
        assertEq(ERC20(DAI).balanceOf(maker), order1OutputAmount);
        assertEq(ERC20(DAI).balanceOf(address(executor)), excessOutputAmount);

        bytes memory swapData2 =
            hex"0502b1c5000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000618c408b320a7840010000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000180000000000000003b6d0340c3d03e4f041fd4cd388c549ee2a29a9e5075882fcfee7c08";
        dloReactor.execute(
            SignedOrder(abi.encode(order2), signOrder(makerPrivateKey, PERMIT2, order2)),
            address(executor),
            abi.encode(new address[](0), swapData2)
        );

        assertEq(ERC20(WETH).balanceOf(maker), 0);
        assertEq(ERC20(DAI).balanceOf(maker), 4600 * ONE);
        assertEq(ERC20(DAI).balanceOf(address(executor)), 866703504519833791698);
    }

    // Executor gets 3649024359659405361033 worth of DAI but order requests 4000000000000000000000 so the transfer fails.
    function testSwapWethToDaiViaAggregatorInsufficientOutput() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(WETH), 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 4000 * ONE, 4000 * ONE, address(maker))
        });

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = WETH;

        bytes memory swapData =
            hex"e449022e0000000000000000000000000000000000000000000000001bc16d674ec800000000000000000000000000000000000000000000000000c2cea7eff5540fb3d20000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000060594a405d53811d3bc4766596efd80fd545a270cfee7c08";
        vm.expectRevert(AggregatorExecutor.InsufficientTokenBalance.selector);
        dloReactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, PERMIT2, order)),
            address(executor),
            abi.encode(tokensToApproveForSwapRouter02, swapData)
        );
    }

    // Same as the test above, except the executor does have enough balance so a transfer wouldn't fail, but the trade would eat into the executor balance pre swap.
    function testSwapWethToDaiViaAggregatorInsufficientOutput2() public {
        vm.prank(DAI_WHALE);
        ERC20(DAI).transfer(address(executor), 4000 * ONE);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(WETH), 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 4000 * ONE, 4000 * ONE, address(maker))
        });

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = WETH;

        bytes memory swapData =
            hex"e449022e0000000000000000000000000000000000000000000000001bc16d674ec800000000000000000000000000000000000000000000000000c2cea7eff5540fb3d20000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000060594a405d53811d3bc4766596efd80fd545a270cfee7c08";
        vm.expectRevert(AggregatorExecutor.InsufficientTokenBalance.selector);
        dloReactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, PERMIT2, order)),
            address(executor),
            abi.encode(tokensToApproveForSwapRouter02, swapData)
        );
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {AggregatorExecutor} from "../../src/sample-executors/AggregatorExecutor.sol";
import {InputToken, OrderInfo, SignedOrder, ETH_ADDRESS} from "../../src/base/ReactorStructs.sol";
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

// This set of tests will use a mainnet fork to test integration.
contract SwapRouter02IntegrationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant SWAPROUTER02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant AGGREGATOR = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address constant WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint256 constant ONE = 1000000000000000000;

    address maker;
    address maker2;
    uint256 makerPrivateKey;
    uint256 maker2PrivateKey;
    address filler;
    AggregatorExecutor executor;
    DutchLimitOrderReactor dloReactor;

    function setUp() public {
        makerPrivateKey = 0xbabe;
        maker = vm.addr(makerPrivateKey);
        maker2PrivateKey = 0xbeef;
        maker2 = vm.addr(maker2PrivateKey);
        filler = makeAddr("filler");
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 16586505);
        dloReactor = new DutchLimitOrderReactor(PERMIT2, 100, address(0));
        executor = new AggregatorExecutor(address(this), address(dloReactor), address(this), AGGREGATOR, SWAPROUTER02);

        // Maker max approves permit post
        vm.prank(maker);
        ERC20(WETH).approve(PERMIT2, type(uint256).max);

        // Transfer 3 WETH to maker
        vm.prank(WHALE);
        ERC20(WETH).transfer(maker, 3 * ONE);
    }

    function testSwapWethToDaiViaAggregator() public {
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(WETH), 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(address(DAI), 3000 * ONE, 3000 * ONE, address(maker))
        });

        address[] memory tokensToApproveForAggregator = new address[](1);
        tokensToApproveForAggregator[0] = WETH;
        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = DAI;

        // taken from 1inch api
        bytes memory swapData; //todo

        dloReactor.execute(
            SignedOrder(abi.encode(order1), signOrder(makerPrivateKey, PERMIT2, order1)),
            address(executor),
            abi.encode(tokensToApproveForAggregator, tokensToApproveForReactor, swapData)
        );
    }
}

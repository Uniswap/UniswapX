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

// This set of tests will use a mainnet fork to test integration.
contract SwapRouter02IntegrationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
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
        swapRouter02Executor = new SwapRouter02Executor(address(this), address(this));
        dloReactor = new DutchLimitOrderReactor(PERMIT2, 100, address(0));

        // Maker max approves permit post
        vm.prank(maker);
        ERC20(WETH).approve(PERMIT2, type(uint256).max);

        // Transfer 2 WETH to maker
        vm.prank(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        ERC20(WETH).transfer(maker, 2 * ONE);
    }

    // Maker's order consists of input = 2 WETH & output = 3000 USDC. There will be 7560391
    // excess wei of USDC in uniswapV3Executor.
    function testSwap2WethToUsdc() public {
        uint256 inputAmount = 2 * ONE;

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(WETH), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(DAI), 3000 * ONE, 3000 * ONE, address(maker))
        });
        address[] memory tokensToApprove = new address[](1);
        tokensToApprove[0] = WETH;
        bytes[] memory multicallData = new bytes[](1);
        multicallData[0] = bytes("");

        assertEq(ERC20(WETH).balanceOf(maker), 2 * ONE);
        assertEq(ERC20(DAI).balanceOf(maker), 0);
        assertEq(ERC20(WETH).balanceOf(address(swapRouter02Executor)), 0);
        dloReactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, PERMIT2, order)),
            address(swapRouter02Executor),
            abi.encode(tokensToApprove, multicallData)
        );
        assertEq(ERC20(WETH).balanceOf(maker), 0);
        assertEq(ERC20(DAI).balanceOf(maker), 3000 * ONE);
        assertEq(ERC20(DAI).balanceOf(address(swapRouter02Executor)), 200 * ONE);
    }
}

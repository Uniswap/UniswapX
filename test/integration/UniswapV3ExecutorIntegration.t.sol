// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {UniswapV3Executor} from "../../src/sample-executors/UniswapV3Executor.sol";
import {InputToken, OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchInput} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";

// This set of tests will use a mainnet fork to test integration.
contract UniswapV3ExecutorIntegrationTest is Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;

    address constant PROTOCOL_FEE_RECIPIENT = address(1);
    uint256 constant PROTOCOL_FEE_BPS = 5000;
    address constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant swapRouter02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    address maker;
    uint256 makerPrivateKey;
    UniswapV3Executor uniswapV3Executor;
    ISignatureTransfer permit2;
    DutchLimitOrderReactor dloReactor;

    function setUp() public {
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 15327550);
        permit2 = ISignatureTransfer(deployPermit2());
        dloReactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        uniswapV3Executor = new UniswapV3Executor(address(dloReactor), swapRouter02, address(this));

        // Maker max approves permit post
        vm.prank(maker);
        ERC20(weth).approve(address(permit2), type(uint256).max);

        // Transfer 0.02 WETH to maker
        vm.prank(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        ERC20(weth).transfer(maker, 20000000000000000);
    }

    // Maker's order consists of input = 0.02WETH & output = 30 USDC. There will be 7560391
    // excess wei of USDC in uniswapV3Executor.
    function testExecute() public {
        uint256 inputAmount = 20000000000000000;
        uint24 fee = 3000;

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(weth), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(usdc), 30000000, 30000000, address(maker))
        });

        assertEq(ERC20(weth).balanceOf(maker), 20000000000000000);
        assertEq(ERC20(usdc).balanceOf(maker), 0);
        assertEq(ERC20(weth).balanceOf(address(uniswapV3Executor)), 0);
        dloReactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(uniswapV3Executor),
            abi.encodePacked(address(weth), fee, address(usdc))
        );
        assertEq(ERC20(weth).balanceOf(maker), 0);
        assertEq(ERC20(usdc).balanceOf(maker), 30000000);
        assertEq(ERC20(usdc).balanceOf(address(uniswapV3Executor)), 7560391);
    }

    // Maker's order consists of input = 0.02WETH & output = 40 USDC. This is too much output, and
    // would require 21299032581776638 wei of WETH. The test will fail when reactor attempts
    // to transfer 40 USDC from executor to the maker pool.
    function testExecuteTooMuchOutput() public {
        uint256 inputAmount = 20000000000000000;
        uint24 fee = 3000;

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(weth), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(usdc), 40000000, 40000000, address(maker))
        });

        vm.expectRevert("TRANSFER_FROM_FAILED");
        dloReactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(uniswapV3Executor),
            abi.encodePacked(address(weth), fee, address(usdc))
        );
    }
}

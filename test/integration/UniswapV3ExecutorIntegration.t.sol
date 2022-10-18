pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {UniswapV3Executor} from "../../src/sample-executors/UniswapV3Executor.sol";
import {InputToken, OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchInput} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import "forge-std/console.sol";

// This set of tests will use a mainnet fork to test integration.
contract UniswapV3ExecutorIntegrationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address swapRouter02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address maker;
    uint256 makerPrivateKey;
    UniswapV3Executor uniswapV3Executor;
    PermitPost permitPost;
    DutchLimitOrderReactor dloReactor;

    function setUp() public {
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 15327550);
        uniswapV3Executor = new UniswapV3Executor(swapRouter02, address(this));
        permitPost = new PermitPost();
        dloReactor = new DutchLimitOrderReactor(address(permitPost));

        // Maker max approves permit post
        vm.prank(maker);
        ERC20(weth).approve(address(permitPost), type(uint256).max);

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
            input: DutchInput(address(weth), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(usdc), 30000000, 30000000, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        assertEq(ERC20(weth).balanceOf(maker), 20000000000000000);
        assertEq(ERC20(usdc).balanceOf(maker), 0);
        assertEq(ERC20(weth).balanceOf(address(uniswapV3Executor)), 0);
        dloReactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(
                    vm,
                    makerPrivateKey,
                    address(permitPost),
                    order.info,
                    InputToken(order.input.token, order.input.endAmount),
                    orderHash
                )
            ),
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
            input: DutchInput(address(weth), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(usdc), 40000000, 40000000, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        vm.expectRevert("TRANSFER_FROM_FAILED");
        dloReactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(
                    vm,
                    makerPrivateKey,
                    address(permitPost),
                    order.info,
                    InputToken(order.input.token, order.input.endAmount),
                    orderHash
                )
            ),
            address(uniswapV3Executor),
            abi.encodePacked(address(weth), fee, address(usdc))
        );
    }
}

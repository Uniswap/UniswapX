pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {UniswapV3Executor} from "../../src/sample-executors/UniswapV3Executor.sol";
import {Output, TokenAmount, OrderInfo} from "../../src/lib/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
import {DutchLimitOrderReactor, DutchLimitOrder} from "../../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";

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
        uniswapV3Executor = new UniswapV3Executor(swapRouter02);
        permitPost = new PermitPost();
        dloReactor = new DutchLimitOrderReactor(address(permitPost));

        // Maker max approves permit post
        vm.prank(maker);
        ERC20(weth).approve(address(permitPost), type(uint256).max);

        // Transfer 0.02 WETH to maker
        vm.prank(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        ERC20(weth).transfer(maker, 20000000000000000);
    }

    // Maker's order consists of input = 0.02WETH & output = 30 USDC. There will be 4025725858800932
    // excess wei of USDC in uniswapV3Executor
    function testExecute() public {
        uint inputAmount = 20000000000000000;
        uint24 fee = 3000;

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(weth), inputAmount),
            outputs: OutputsBuilder.singleDutch(address(usdc), 30000000, 30000000, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        assertEq(ERC20(weth).balanceOf(maker), 20000000000000000);
        assertEq(ERC20(usdc).balanceOf(maker), 0);
        assertEq(ERC20(weth).balanceOf(address(uniswapV3Executor)), 0);
        dloReactor.execute(
            order,
            getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({
                    token: address(weth),
                    spender: address(dloReactor),
                    maxAmount: inputAmount,
                    deadline: order.info.deadline
                }),
                0,
                uint256(orderHash)
            ),
            address(uniswapV3Executor),
            abi.encode(fee, dloReactor)
        );
        assertEq(ERC20(weth).balanceOf(maker), 0);
        assertEq(ERC20(usdc).balanceOf(maker), 30000000);
        assertEq(ERC20(weth).balanceOf(address(uniswapV3Executor)), 4025725858800932);
    }

    // Maker's order consists of input = 0.02WETH & output = 40 USDC. This is too much output, and
    // would require 21299032581776638 wei of WETH. The test will fail when router attempts
    // to transfer this amount of WETH from executor to the USDC/WETH pool.
    function testExecuteTooMuchOutput() public {
        uint inputAmount = 20000000000000000;
        uint24 fee = 3000;

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(weth), inputAmount),
            outputs: OutputsBuilder.singleDutch(address(usdc), 40000000, 40000000, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        vm.expectRevert(bytes("STF"));
        dloReactor.execute(
            order,
            getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({
                    token: address(weth),
                    spender: address(dloReactor),
                    maxAmount: inputAmount,
                    deadline: order.info.deadline
                }),
                0,
                uint256(orderHash)
            ),
            address(uniswapV3Executor),
            abi.encode(fee, dloReactor)
        );
    }
}
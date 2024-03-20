// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SwapRouter02Executor} from "../../src/sample-executors/SwapRouter02Executor.sol";
import {InputToken, OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {V2DutchOrderReactor, V2DutchOrder, DutchInput, DutchOutput} from "../../src/reactors/V2DutchOrderReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ISwapRouter02, ExactInputSingleParams} from "../../src/external/ISwapRouter02.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

// This set of tests will use a mainnet fork to test integration.
contract DutchV2Integration is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using SafeTransferLib for ERC20;

    ERC20 constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    uint256 constant ONE = 1000000000000000000;

    address swapper;
    address swapper2;
    uint256 swapperPrivateKey;
    uint256 swapper2PrivateKey;
    address filler;
    SwapRouter02Executor swapRouter02Executor;
    V2DutchOrderReactor reactor;

    function setUp() public {
        swapperPrivateKey = 0xbabe;
        swapper = vm.addr(swapperPrivateKey);
        swapper2PrivateKey = 0xbeef;
        swapper2 = vm.addr(swapper2PrivateKey);
        filler = makeAddr("filler");
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 19464520);
        // reactor = new V2DutchOrderReactor(PERMIT2, address(0));
        reactor = V2DutchOrderReactor(payable(0x3867393cC6EA7b0414C2c3e1D9fe7cEa987Fd066));

        // Swapper max approves permit post
        vm.prank(swapper);
        WETH.approve(address(PERMIT2), type(uint256).max);
        vm.prank(swapper);
        USDC.approve(address(PERMIT2), type(uint256).max);

        // Transfer 3 WETH to swapper
        vm.prank(WHALE);
        deal(address(USDC), swapper, 3 * ONE);
    }

    // Swapper creates below 2 orders, and both are filled via SwapRouter02Executor via Uniswap V3.
    // Order 1: input = 2 WETH, output = 3000 DAI
    // Order 2: input = 1 WETH, output = 1600 DAI
    // I chose to test using 2 orders to test that the 2nd execute call will not have to pass in
    // `tokensToApproveForSwapRouter02`
    // There will be 288797467469336654155 wei of DAI in SwapRouter02Executor after the 1st order is filled.
    // There will be 332868886072663242927 wei of DAI in SwapRouter02Executor after the 2nd order is filled.
    function testSwap() public {
        bytes memory order = hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000b19ca5a7aca9369e0946e15cd1ce2c58c8fe4ad000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000003600000000000000000000000003867393cc6ea7b0414c2c3e1d9fe7cea987fd0660000000000000000000000005d5577a33abbbae5e7235d2d080caff47e94b7d000000000000000000000000000000000000000000000000000000000000000c80000000000000000000000000000000000000000000000000000000065fb4fa5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000005d5577a33abbbae5e7235d2d080caff47e94b7d00000000000000000000000000000000000000000000000000000000065fb4f9b0000000000000000000000000000000000000000000000000000000065fb4fa5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000041eda00022ee9e1fa1b2ea84c276769f51a2367eec05ef3935e37cfb3a39529b2a082651ee13ebfbc0e6e69113ac7c70661012a2364988193b820190fc528346391b00000000000000000000000000000000000000000000000000000000000000";

        bytes memory sig = hex"83c1a4af8191132eae6b7b7336da8567e271a6340c5399bdcb9772574e88bb3405ab8ae03a8601d9da4b888f36d1eb3a7be1a9d16893fe646b325ebd780532931b";

        SignedOrder memory signed = SignedOrder({
            order: order,
            sig: sig
        });

        console2.log("hi");
        V2DutchOrder memory order2 = abi.decode(
            order,
            (V2DutchOrder)
        );
        console2.log(order2.info.swapper);

        vm.prank(swapper);
        reactor.execute(signed);
    }
}

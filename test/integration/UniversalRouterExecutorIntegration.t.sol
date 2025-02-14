// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {UniversalRouterExecutor} from "../../src/sample-executors/UniversalRouterExecutor.sol";
import {InputToken, OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {DutchOrderReactor, DutchOrder, DutchInput, DutchOutput} from "../../src/reactors/DutchOrderReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {IReactor} from "../../src/interfaces/IReactor.sol";
import {IUniversalRouter} from "../../src/external/IUniversalRouter.sol";

contract UniversalRouterExecutorIntegrationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using SafeTransferLib for ERC20;

    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 constant USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    uint256 constant USDC_ONE = 1e6;

    // UniversalRouter with V4 support
    IUniversalRouter universalRouter = IUniversalRouter(0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af);
    IPermit2 permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    address swapper;
    uint256 swapperPrivateKey;
    address whitelistedCaller;
    address owner;
    UniversalRouterExecutor universalRouterExecutor;
    DutchOrderReactor reactor;

    // UniversalRouter commands
    uint256 constant V3_SWAP_EXACT_IN = 0x00;

    function setUp() public {
        swapperPrivateKey = 0xbeef;
        swapper = vm.addr(swapperPrivateKey);
        vm.label(swapper, "swapper");
        whitelistedCaller = makeAddr("whitelistedCaller");
        owner = makeAddr("owner");
        // 02-10-2025
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 21818802);
        reactor = new DutchOrderReactor(permit2, address(0));
        address[] memory whitelistedCallers = new address[](1);
        whitelistedCallers[0] = whitelistedCaller;
        universalRouterExecutor = new UniversalRouterExecutor(
            whitelistedCallers, IReactor(address(reactor)), owner, address(universalRouter), permit2
        );

        vm.prank(swapper);
        USDC.approve(address(permit2), type(uint256).max);

        deal(address(USDC), swapper, 100 * 1e6);
    }

    function baseTest(DutchOrder memory order) internal {
        _baseTest(order, false, "");
    }

    function _baseTest(DutchOrder memory order, bool expectRevert, bytes memory revertData) internal {
        address[] memory tokensToApproveForPermit2AndUniversalRouter = new address[](1);
        tokensToApproveForPermit2AndUniversalRouter[0] = address(USDC);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(USDT);

        bytes memory commands = hex"00";
        bytes[] memory inputs = new bytes[](1);
        // V3 swap USDC -> USDT, with recipient as universalRouterExecutor
        inputs[0] =
            hex"0000000000000000000000002e234DAe75C793f67A35089C9d99245E1C58470b0000000000000000000000000000000000000000000000000000000000989680000000000000000000000000000000000000000000000000000000000090972200000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002ba0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000064dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000000000";

        bytes memory data =
            abi.encodeWithSelector(IUniversalRouter.execute.selector, commands, inputs, uint256(block.timestamp + 1000));

        vm.prank(whitelistedCaller);
        if (expectRevert) {
            vm.expectRevert(revertData);
        }
        universalRouterExecutor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            abi.encode(tokensToApproveForPermit2AndUniversalRouter, tokensToApproveForReactor, data)
        );
    }

    function test_universalRouterExecutor() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(USDC, 10 * USDC_ONE, 10 * USDC_ONE),
            outputs: OutputsBuilder.singleDutch(address(USDT), 9 * USDC_ONE, 9 * USDC_ONE, address(swapper))
        });

        address[] memory tokensToApproveForPermit2AndUniversalRouter = new address[](1);
        tokensToApproveForPermit2AndUniversalRouter[0] = address(USDC);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(USDT);

        uint256 swapperInputBalanceBefore = USDC.balanceOf(swapper);
        uint256 swapperOutputBalanceBefore = USDT.balanceOf(swapper);

        baseTest(order);

        assertEq(USDC.balanceOf(swapper), swapperInputBalanceBefore - 10 * USDC_ONE);
        assertEq(USDT.balanceOf(swapper), swapperOutputBalanceBefore + 9 * USDC_ONE);
        // Expect some USDT to be left in the executor from the swap
        assertGe(USDT.balanceOf(address(universalRouterExecutor)), 0);
    }

    function test_universalRouterExecutor_TooLittleReceived() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(USDC, 10 * USDC_ONE, 10 * USDC_ONE),
            // Too much output
            outputs: OutputsBuilder.singleDutch(address(USDT), 11 * USDC_ONE, 11 * USDC_ONE, address(swapper))
        });

        _baseTest(order, true, bytes("TRANSFER_FROM_FAILED"));
    }

    function test_universalRouterExecutor_onlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        address recipient = makeAddr("recipient");
        uint256 recipientBalanceBefore = recipient.balance;
        uint256 recipientUSDCBalanceBefore = USDC.balanceOf(recipient);

        vm.deal(address(universalRouterExecutor), 1 ether);
        deal(address(USDC), address(universalRouterExecutor), 100 * USDC_ONE);

        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        universalRouterExecutor.withdrawETH(recipient);

        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        universalRouterExecutor.withdrawERC20(USDC, recipient);

        vm.prank(owner);
        universalRouterExecutor.withdrawETH(recipient);
        assertEq(address(recipient).balance, recipientBalanceBefore + 1 ether);

        vm.prank(owner);
        universalRouterExecutor.withdrawERC20(USDC, recipient);
        assertEq(USDC.balanceOf(recipient), recipientUSDCBalanceBefore + 100 * USDC_ONE);
        assertEq(USDC.balanceOf(address(universalRouterExecutor)), 0);
    }
}

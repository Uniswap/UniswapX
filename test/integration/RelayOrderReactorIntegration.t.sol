// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import "forge-std/console.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Test} from "forge-std/Test.sol";
import {
    OrderInfo,
    InputTokenWithRecipient,
    OutputToken,
    ResolvedRelayOrder,
    SignedOrder
} from "../../src/base/ReactorStructs.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {RelayOrderLib, RelayOrder, ActionType} from "../../src/lib/RelayOrderLib.sol";
import {RelayOrderReactor} from "../../src/reactors/RelayOrderReactor.sol";
import {PermitExecutor} from "../../src/sample-executors/PermitExecutor.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";

contract RelayOrderReactorIntegrationTest is GasSnapshot, Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using RelayOrderLib for RelayOrder;

    uint256 constant ONE = 10 ** 18;

    ERC20 constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 constant UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    ERC20 constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant WHALE = 0x55FE002aefF02F77364de339a1292923A15844B8;
    address constant UNIVERSAL_ROUTER = 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD;
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    uint256 swapperPrivateKey;
    uint256 swapper2PrivateKey;
    address swapper;
    address swapper2;
    address filler;
    RelayOrderReactor reactor;
    PermitExecutor permitExecutor;

    error InvalidNonce();
    error InvalidSigner();

    function setUp() public {
        swapperPrivateKey = 0xbabe;
        swapper = vm.addr(swapperPrivateKey);
        swapper2PrivateKey = 0xbeef;
        swapper2 = vm.addr(swapper2PrivateKey);
        filler = makeAddr("filler");
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 17972788);
        reactor = new RelayOrderReactor{salt: bytes32(0x00)}(PERMIT2, address(0), UNIVERSAL_ROUTER);
        assertEq(
            address(reactor), 0x378718523232A14BE8A24e291b5A5075BE04D121, "Reactor address does not match expected"
        );
        permitExecutor = new PermitExecutor(address(filler), reactor, address(filler));

        // Swapper max approves permit post
        vm.startPrank(swapper);
        DAI.approve(address(PERMIT2), type(uint256).max);
        USDC.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(DAI), address(reactor), type(uint160).max, type(uint48).max);
        PERMIT2.approve(address(USDC), address(reactor), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        // reactor max approves permit post
        vm.startPrank(address(reactor));
        DAI.approve(address(PERMIT2), type(uint256).max);
        USDC.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(DAI), UNIVERSAL_ROUTER, type(uint160).max, type(uint48).max);
        PERMIT2.approve(address(USDC), UNIVERSAL_ROUTER, type(uint160).max, type(uint48).max);
        vm.stopPrank();

        // Transfer 1000 DAI to swapper
        vm.startPrank(WHALE);
        DAI.transfer(swapper, 1000 * ONE);
        DAI.transfer(swapper2, 1000 * ONE);
        USDC.transfer(swapper, 1000 * 10 ** 6);
        USDC.transfer(swapper2, 1000 * 10 ** 6);
        vm.stopPrank();
    }

    // swapper creates one order containing a universal router swap for 100 DAI -> USDC
    // order contains two inputs: DAI for the swap and USDC as gas payment for fillers
    // at the forked block, 95276229 is the minAmountOut
    function testExecute() public {
        InputTokenWithRecipient[] memory inputTokens = new InputTokenWithRecipient[](2);
        inputTokens[0] =
            InputTokenWithRecipient({token: DAI, amount: 100 * ONE, maxAmount: 100 * ONE, recipient: UNIVERSAL_ROUTER});
        inputTokens[1] =
            InputTokenWithRecipient({token: USDC, amount: 10 * 10 ** 6, maxAmount: 10 * 10 ** 6, recipient: address(0)});

        uint256 amountOutMin = 95 * 10 ** 6;

        bytes[] memory actions = new bytes[](1);
        bytes memory DAI_USDC_UR_CALLDATA =
            hex"24856bc30000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000100000000000000000000000000378718523232a14be8a24e291b5a5075be04d1210000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000000000000000000000000000000000000005adccc500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b6b175474e89094c44da98b954eedeac495271d0f000064a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000";
        actions[0] = abi.encode(ActionType.UniversalRouter, DAI_USDC_UR_CALLDATA);

        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            actions: actions,
            inputs: inputTokens,
            outputs: OutputsBuilder.single(address(USDC), amountOutMin, address(swapper))
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        uint256 routerDaiBalanceBefore = DAI.balanceOf(UNIVERSAL_ROUTER);

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecute");
        reactor.execute(signedOrder);
        snapEnd();

        assertEq(DAI.balanceOf(UNIVERSAL_ROUTER), routerDaiBalanceBefore, "No leftover input in router");
        assertEq(USDC.balanceOf(address(reactor)), 0, "No leftover output in reactor");
        assertGe(USDC.balanceOf(swapper), amountOutMin, "Swapper did not receive enough output");
        assertEq(USDC.balanceOf((filler)), 10 * 10 ** 6, "filler did not receive enough USDC");
    }

    function testPermitAndExecute() public {
        // this swapper has not yet approved the P2 contract
        // so we will relay a USDC 2612 permit to the P2 contract first
        // making a USDC -> DAI swap
        InputTokenWithRecipient[] memory inputTokens = new InputTokenWithRecipient[](2);
        inputTokens[0] = InputTokenWithRecipient({
            token: USDC,
            amount: 100 * 10 ** 6,
            maxAmount: 100 * 10 ** 6,
            recipient: UNIVERSAL_ROUTER
        });
        inputTokens[1] =
            InputTokenWithRecipient({token: USDC, amount: 10 * 10 ** 6, maxAmount: 10 * 10 ** 6, recipient: address(0)});

        uint256 amountOutMin = 95 * ONE;

        // sign permit for USDC
        uint256 amount = type(uint256).max - 1; // infinite approval to permit2
        uint256 deadline = type(uint256).max - 1; // never expires
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                USDC.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        swapper2,
                        address(PERMIT2),
                        amount,
                        USDC.nonces(swapper2),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(swapper2PrivateKey, digest);
        address signer = ecrecover(digest, v, r, s);
        assertEq(signer, swapper2);

        bytes memory permitData =
            abi.encode(address(USDC), abi.encode(swapper2, address(PERMIT2), amount, deadline, v, r, s));

        bytes[] memory actions = new bytes[](1);
        bytes memory USDC_DAI_UR_CALLDATA =
            hex"24856bc30000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000100000000000000000000000000378718523232a14be8a24e291b5a5075be04d1210000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000000000000000000000000005297ede6cd16022cc00000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002ba0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000646b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000";
        actions[0] = abi.encode(ActionType.UniversalRouter, USDC_DAI_UR_CALLDATA);

        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100),
            actions: actions,
            inputs: inputTokens,
            outputs: OutputsBuilder.single(address(DAI), amountOutMin, address(swapper2))
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapper2PrivateKey, address(PERMIT2), order));

        uint256 routerUSDCBalanceBefore = USDC.balanceOf(UNIVERSAL_ROUTER);

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testPermitAndExecute");
        permitExecutor.executeWithPermit(signedOrder, permitData);
        snapEnd();

        assertEq(USDC.balanceOf(UNIVERSAL_ROUTER), routerUSDCBalanceBefore, "No leftover input in router");
        assertEq(DAI.balanceOf(address(reactor)), 0, "No leftover output in reactor");
        assertGe(DAI.balanceOf(swapper2), amountOutMin, "Swapper did not receive enough output");
        // in this case, gas payment will go to executor
        assertEq(USDC.balanceOf(address(permitExecutor)), 10 * 10 ** 6, "filler did not receive enough USDC");
    }
}

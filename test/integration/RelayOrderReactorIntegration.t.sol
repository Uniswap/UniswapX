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
            address(reactor), 0x5113962BeEA7A276a30ca08e53bA3E2B05323fa2, "Reactor address does not match expected"
        );

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
        // Transfer 100 USDC to swapper
        USDC.transfer(swapper, 100 * 10 ** 6);
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

        uint256 amountOutMin = 95276229;

        bytes[] memory actions = new bytes[](1);
        bytes memory DAI_USDC_UR_CALLDATA =
            hex"24856bc300000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001000000000000000000000000005113962beea7a276a30ca08e53ba3e2b05323fa20000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000000000000000000000000000000000000005adccc500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b6b175474e89094c44da98b954eedeac495271d0f000064a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000";
        actions[0] = abi.encode(ActionType.UniversalRouter, DAI_USDC_UR_CALLDATA);

        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            actions: actions,
            inputs: inputTokens,
            outputs: OutputsBuilder.single(address(USDC), amountOutMin, address(swapper))
        });

        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(PERMIT2), order));

        vm.prank(filler);
        snapStart("RelayOrderReactorIntegrationTest-testExecute");
        reactor.execute(signedOrder);
        snapEnd();

        assertGe(USDC.balanceOf(swapper), amountOutMin, "Swapper did not enough DAI");
        assertEq(USDC.balanceOf((filler)), 10 * 10 ** 6, "filler did not receive enough USDC");
    }
}

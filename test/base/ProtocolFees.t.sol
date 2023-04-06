// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {SignedOrder, OrderInfo} from "../../src/base/ReactorStructs.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ProtocolFees} from "../../src/base/ProtocolFees.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchInput,
    DutchOutput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";

contract ProtocolFeesTest is Test, DeployPermit2, GasSnapshot, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    address constant PROTOCOL_FEE_RECIPIENT = address(2);
    address constant GOVERNANCE = address(3);
    address constant INTERFACE_FEE_RECIPIENT = address(4);
    uint256 constant ONE = 10 ** 18;

    MockERC20 tokenIn1;
    MockERC20 tokenOut1;
    uint256 makerPrivateKey1;
    address maker1;
    uint256 makerPrivateKey2;
    address maker2;
    DutchLimitOrderReactor reactor;
    IAllowanceTransfer permit2;
    MockFillContract fillContract;

    function setUp() public {
        tokenIn1 = new MockERC20("tokenIn1", "IN1", 18);
        tokenOut1 = new MockERC20("tokenOut1", "OUT1", 18);
        fillContract = new MockFillContract();
        makerPrivateKey1 = 0x12341234;
        maker1 = vm.addr(makerPrivateKey1);
        makerPrivateKey2 = 0x12341235;
        maker2 = vm.addr(makerPrivateKey2);
        permit2 = IAllowanceTransfer(deployPermit2());
        reactor = new DutchLimitOrderReactor(address(permit2), GOVERNANCE, PROTOCOL_FEE_RECIPIENT);
        tokenIn1.forceApprove(maker1, address(permit2), type(uint256).max);
        tokenIn1.forceApprove(maker2, address(permit2), type(uint256).max);

        vm.prank(GOVERNANCE);
        reactor.setProtocolFees(address(tokenOut1), 5);
    }

    function test1OutputWithProtocolFee() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenOut1.mint(address(fillContract), ONE);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), ONE * 9995 / 10000, ONE * 9995 / 10000, maker1, false);
        dutchOutputs[1] =
            DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, PROTOCOL_FEE_RECIPIENT, false);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesTest1OutputWithProtocolFee");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), ONE);
        assertEq(tokenOut1.balanceOf(address(fillContract)), 0);
        assertEq(tokenOut1.balanceOf(maker1), ONE * 9995 / 10000);
        assertEq(tokenOut1.balanceOf(PROTOCOL_FEE_RECIPIENT), ONE * 5 / 10000);
    }

    function test1OutputWithProtocolFeeAndInterfaceFee() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenOut1.mint(address(fillContract), ONE);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](3);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), ONE * 9990 / 10000, ONE * 9990 / 10000, maker1, false);
        dutchOutputs[1] =
            DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, PROTOCOL_FEE_RECIPIENT, false);
        dutchOutputs[2] =
            DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, INTERFACE_FEE_RECIPIENT, false);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesTest1OutputWithProtocolFeeAndInterfaceFee");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), ONE);
        assertEq(tokenOut1.balanceOf(address(fillContract)), 0);
        assertEq(tokenOut1.balanceOf(maker1), ONE * 9990 / 10000);
        assertEq(tokenOut1.balanceOf(PROTOCOL_FEE_RECIPIENT), ONE * 5 / 10000);
        assertEq(tokenOut1.balanceOf(INTERFACE_FEE_RECIPIENT), ONE * 5 / 10000);
    }

    function test1OutputWithProtocolFeeAndInterfaceFeeInsufficientProtocolFee() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenOut1.mint(address(fillContract), ONE);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](3);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), ONE * 9990 / 10000, ONE * 9990 / 10000, maker1, false);
        dutchOutputs[1] =
            DutchOutput(address(tokenOut1), ONE * 4 / 10000, ONE * 4 / 10000, PROTOCOL_FEE_RECIPIENT, false);
        dutchOutputs[2] =
            DutchOutput(address(tokenOut1), ONE * 5 / 10000, ONE * 5 / 10000, INTERFACE_FEE_RECIPIENT, false);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        vm.expectRevert(ProtocolFees.InsufficientProtocolFee.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
    }
}

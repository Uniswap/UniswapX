// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfo, SignedOrder, ETH_ADDRESS} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchInput,
    DutchOutput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

// This contract will test ETH outputs using DutchLimitOrderReactor as the reactor and MockFillContract for fillContract.
contract EthOutputTest is Test, DeployPermit2, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    address constant PROTOCOL_FEE_RECIPIENT = address(2);
    uint256 constant PROTOCOL_FEE_BPS = 5000;
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
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        tokenIn1.forceApprove(maker1, address(permit2), type(uint256).max);
        tokenIn1.forceApprove(maker2, address(permit2), type(uint256).max);
    }

    // Fill one order (from maker1, input = 1 tokenIn, output = 0.5 ETH (starts at 1 but decays to 0.5))
    function testEthOutput() public {
        tokenIn1.mint(address(maker1), ONE);
        vm.deal(address(fillContract), ONE);

        vm.warp(1000);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(ETH_ADDRESS, ONE, 0, maker1)
        });
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenIn1.balanceOf(address(fillContract)), ONE);
        // There is 0.5 ETH remaining in the fillContract as output has decayed to 0.5 ETH
        assertEq(address(fillContract).balance, ONE / 2);
        assertEq(address(maker1).balance, ONE / 2);
    }

    // Fill 3 orders
    // order 1: by maker1, input = 1 tokenIn1, output = [2 ETH, 3 tokenOut1]
    // order 2: by maker2, input = 2 tokenIn1, output = [3 ETH]
    // order 3: by maker2, input = 3 tokenIn1, output = [4 tokenOut1]
    function test3OrdersWithEthAndERC20Outputs() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenIn1.mint(address(maker2), ONE * 5);
        tokenOut1.mint(address(fillContract), ONE * 7);
        vm.deal(address(fillContract), ONE * 5);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(ETH_ADDRESS, 2 * ONE, 2 * ONE, maker1, false);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), 3 * ONE, 3 * ONE, maker1, false);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker2).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(ETH_ADDRESS, 3 * ONE, 3 * ONE, maker2)
        });
        DutchLimitOrder memory order3 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker2).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), 3 * ONE, 3 * ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), 4 * ONE, 4 * ONE, maker2)
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](3);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(makerPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(makerPrivateKey2, address(permit2), order2));
        signedOrders[2] = SignedOrder(abi.encode(order3), signOrder(makerPrivateKey2, address(permit2), order3));
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));

        assertEq(tokenOut1.balanceOf(maker1), 3 * ONE);
        assertEq(maker1.balance, 2 * ONE);
        assertEq(maker2.balance, 3 * ONE);
        assertEq(tokenOut1.balanceOf(maker2), 4 * ONE);
        assertEq(tokenIn1.balanceOf(address(fillContract)), 6 * ONE);
        assertEq(address(fillContract).balance, 0);
    }
}

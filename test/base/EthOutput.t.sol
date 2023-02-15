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
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "../../src/external/ISignatureTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchInput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchLimitOrder, DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

// This suite of tests test execution with a mock fill contract.
contract DirectTakerFillMacroTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using DutchLimitOrderLib for DutchLimitOrder;

    address constant PROTOCOL_FEE_RECIPIENT = address(2);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 makerPrivateKey;
    address maker;
    address directTaker;
    DutchLimitOrderReactor reactor;
    ISignatureTransfer permit2;

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        directTaker = address(888);
        permit2 = deployPermit2();
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
    }

    // Execute a single order, input = 1 and outputs = [2].
    function testSingleOutput() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(directTaker, outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);
        tokenOut.forceApprove(directTaker, address(permit2), type(uint256).max);
        vm.prank(directTaker);
        permit2.approve(address(tokenOut), address(reactor), type(uint160).max, type(uint48).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        snapStart("DirectTakerFillMacroSingleOutput");
        vm.prank(directTaker);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)), address(1), bytes("")
        );
        snapEnd();
        assertEq(tokenOut.balanceOf(maker), outputAmount);
        assertEq(tokenIn.balanceOf(directTaker), inputAmount);
    }
}

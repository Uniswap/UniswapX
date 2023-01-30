// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchInput} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {InvariantTest} from "../util/InvariantTest.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchLimitOrder, DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

contract Runner is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using DutchLimitOrderLib for DutchLimitOrder;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 maker1pk = 0x100001;
    address maker1 = vm.addr(maker1pk);
    DutchLimitOrderReactor reactor;
    ISignatureTransfer permit2;
    uint256 constant ONE = 10 ** 18;

    constructor(ISignatureTransfer _permit2) {
        permit2 = _permit2;
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        reactor = new DutchLimitOrderReactor(address(permit2), 5000, address(888));
    }

    function makerCreatesOrder() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, ONE, address(maker1))
        });
        bytes memory encodedOrder = abi.encode(order);
        bytes memory orderSig = signOrder(maker1pk, address(permit2), order);
    }
}

contract GoudaInvariants is Test, InvariantTest, DeployPermit2 {
    ISignatureTransfer permit2;
    Runner runner;

    function setUp() public {
        vm.warp(1000);
        permit2 = deployPermit2();
        runner = new Runner(permit2);
        addTargetContract(address(runner));
    }

    function invariant_sanityCheck() public {
        assertEq(uint(1), uint(1));
    }
}

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

    uint256 constant ONE = 10 ** 18;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 maker1pk = 0x100001;
    address maker1 = vm.addr(maker1pk);
    uint256 maker1Nonce;
    DutchLimitOrderReactor reactor;
    address permit2;

    SignedOrder[] signedOrders;
    bool[] signedOrdersFilled;

    constructor(address _permit2) {
        permit2 = _permit2;
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        reactor = new DutchLimitOrderReactor(permit2, 5000, address(888));

        tokenIn.mint(address(maker1), ONE * 999999);
        tokenOut.mint(address(fillContract), ONE * 999999);
        tokenIn.forceApprove(maker1, permit2, type(uint256).max);
    }

    function makerCreatesOrder() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100).withNonce(maker1Nonce),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, ONE, address(maker1))
        });
        SignedOrder memory signedOrder = SignedOrder(abi.encode(order), signOrder(maker1pk, permit2, order));
        signedOrders.push(signedOrder);
        signedOrdersFilled.push(false);
        maker1Nonce++;
    }

    function fillerExecutesOrder(uint256 index) public {
        if (signedOrders.length == 0) {
            return;
        }
        if (signedOrdersFilled[index % signedOrders.length]) {
            return;
        }
        reactor.execute(
            signedOrders[index % signedOrders.length],
            address(fillContract),
            bytes("")
        );
        signedOrdersFilled[index % signedOrders.length] = true;
    }
}

contract GoudaInvariants is Test, InvariantTest, DeployPermit2 {
    address permit2;
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

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchInput,
    ResolvedOrder
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {InvariantTest} from "../util/InvariantTest.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchLimitOrder, DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import "forge-std/console.sol";

contract Runner is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using DutchLimitOrderLib for DutchLimitOrder;

    uint256 constant ONE = 10 ** 18;
    uint256 constant INITIAL_BALANCE = ONE * 999999;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 makerPk = 0x100001;
    address maker = vm.addr(makerPk);
    uint256 makerNonce;
    DutchLimitOrderReactor reactor;
    address permit2;
    uint256 cumulativeTokenOut;
    OrderQuoter orderQuoter;

    SignedOrder[] signedOrders;
    bool[] signedOrdersFilled;
    uint256 numOrdersFilled;

    constructor(address _permit2) {
        permit2 = _permit2;
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        reactor = new DutchLimitOrderReactor(permit2, 5000, address(888));
        orderQuoter = new OrderQuoter();

        tokenIn.mint(address(maker), INITIAL_BALANCE);
        tokenOut.mint(address(fillContract), INITIAL_BALANCE);
        tokenIn.forceApprove(maker, permit2, type(uint256).max);
    }

    function makerCreatesOrder(uint256 seed) public {
        uint256 decay = seed % 10;
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                makerNonce
                ),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, ONE * decay / 10, address(maker))
        });
        SignedOrder memory signedOrder = SignedOrder(abi.encode(order), signOrder(makerPk, permit2, order));
        signedOrders.push(signedOrder);
        signedOrdersFilled.push(false);
        makerNonce++;
    }

    function fillerExecutesOrder(uint256 index) public {
        if (signedOrders.length == 0) {
            return;
        }
        if (signedOrdersFilled[index % signedOrders.length]) {
            return;
        }
        console.log("Block.timestamp", block.timestamp);
        ResolvedOrder memory ro = orderQuoter.quote(
            signedOrders[index % signedOrders.length].order, signedOrders[index % signedOrders.length].sig
        );
        console.log("ro.outputs[0].amount");
        console.log(ro.outputs[0].amount);
        reactor.execute(signedOrders[index % signedOrders.length], address(fillContract), bytes(""));
        signedOrdersFilled[index % signedOrders.length] = true;
        numOrdersFilled++;
    }

    function balancesAreCorrect() public returns (bool) {
        if (tokenIn.balanceOf(address(fillContract)) != numOrdersFilled * ONE) {
            return false;
        }
        //        if (tokenOut.balanceOf(address(fillContract)) != (INITIAL_BALANCE - numOrdersFilled * ONE)) {
        //            return false;
        //        }
        if (tokenIn.balanceOf(maker) != (INITIAL_BALANCE - numOrdersFilled * ONE)) {
            return false;
        }
        //        if (tokenOut.balanceOf(maker) != numOrdersFilled * ONE) {
        //            return false;
        //        }
        if (numOrdersFilled == 3) {
            return false;
        }
        return true;
    }
}

contract DecayInvariants is Test, InvariantTest, DeployPermit2 {
    address permit2;
    Runner runner;

    function setUp() public {
        vm.warp(1000);
        permit2 = deployPermit2();
        runner = new Runner(permit2);
        addTargetContract(address(runner));
    }

    function invariant_balancesAreCorrect() public {
        assertTrue(runner.balancesAreCorrect());
    }
}

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
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import "forge-std/console.sol";

struct SignedOrderWithMaker {
    SignedOrder signedOrder;
    address maker;
}

contract Runner is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using DutchLimitOrderLib for DutchLimitOrder;

    uint256 constant ONE = 10 ** 18;
    uint256 constant INITIAL_BALANCE = ONE * 999999;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 maker1Pk = 0x100001;
    address maker1 = vm.addr(maker1Pk);
    uint256 maker1Nonce;
    uint256 maker2Pk = 0x100002;
    address maker2 = vm.addr(maker2Pk);
    uint256 maker2Nonce;
    DutchLimitOrderReactor reactor;
    address permit2;

    SignedOrderWithMaker[] signedOrders;
    bool[] signedOrdersFilled;
    uint256 numOrdersFilled;

    constructor(address _permit2) {
        permit2 = _permit2;
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        reactor = new DutchLimitOrderReactor(permit2, 5000, address(888));

        tokenIn.mint(address(maker1), INITIAL_BALANCE);
        tokenIn.mint(address(maker2), INITIAL_BALANCE);
        tokenOut.mint(address(fillContract), INITIAL_BALANCE);
        tokenIn.forceApprove(maker1, permit2, type(uint256).max);
        tokenIn.forceApprove(maker2, permit2, type(uint256).max);
    }

    function makerCreatesOrder(bool useMaker1) public {
        SignedOrderWithMaker memory signedOrder;
        if (useMaker1) {
            DutchLimitOrder memory order = DutchLimitOrder({
                info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100)
                    .withNonce(maker1Nonce),
                startTime: block.timestamp - 100,
                endTime: block.timestamp + 100,
                input: DutchInput(address(tokenIn), ONE, ONE),
                outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, ONE, address(maker1))
            });
            signedOrder =
                SignedOrderWithMaker(SignedOrder(abi.encode(order), signOrder(maker1Pk, permit2, order)), maker1);
            maker1Nonce++;
        } else {
            DutchLimitOrder memory order = DutchLimitOrder({
                info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker2).withDeadline(block.timestamp + 100)
                    .withNonce(maker2Nonce),
                startTime: block.timestamp - 100,
                endTime: block.timestamp + 100,
                input: DutchInput(address(tokenIn), ONE, ONE),
                outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, ONE, address(maker2))
            });
            signedOrder =
                SignedOrderWithMaker(SignedOrder(abi.encode(order), signOrder(maker2Pk, permit2, order)), maker1);
            maker2Nonce++;
        }
        signedOrders.push(signedOrder);
        signedOrdersFilled.push(false);
    }

    function fillerExecutesOrder(uint256 index) public {
        if (signedOrders.length == 0) {
            return;
        }
        if (signedOrdersFilled[index % signedOrders.length]) {
            return;
        }
        reactor.execute(signedOrders[index % signedOrders.length].signedOrder, address(fillContract), bytes(""));
        signedOrdersFilled[index % signedOrders.length] = true;
        numOrdersFilled++;
    }

    function fillerBatchExecutesOrders(uint256 numOrdersChosenSeed, uint256 randomIndexSeed) public {
        // This counter is used to introduce randomness in interative hashing
        uint256 counter;

        uint256 numUnfilledOrders;
        for (uint256 i = 0; i < signedOrdersFilled.length; i++) {
            if (!signedOrdersFilled[i]) {
                numUnfilledOrders++;
            }
        }
        // Ensure there are at least 4 unfilled orders
        if (numUnfilledOrders < 4) {
            console.log("SKIPPING - less than 4 numUnfilledOrders");
            return;
        }
        console.log("*****NEW RUN*****");
        console.log("length signedOrders", signedOrders.length);
        console.log("length signedOrdersFilled", signedOrdersFilled.length);
        console.log("numUnfilledOrders", numUnfilledOrders);
        // Batch together either 2, 3, or 4 orders
        uint256 numOrdersToFill = (numOrdersChosenSeed % 3) + 2;
        console.log("numOrdersToFill", numOrdersToFill);
        SignedOrder[] memory signedOrdersToFill = new SignedOrder[](numOrdersToFill);
        uint256 numOrdersChosen;
        uint256 randomIndex = randomIndexSeed % signedOrders.length;
        while (numOrdersChosen < numOrdersToFill) {
            console.log("counter", counter);
            console.log("numOrdersChosen", numOrdersChosen);
            console.log("randomIndex", randomIndex);
            counter++;
            //            if (counter == 15) {
            //                console.log("!!!!MANUAL REVERT!!!!!");
            //                revert("Manual revert");
            //            }
            if (signedOrdersFilled[randomIndex]) {
                randomIndex = uint256(keccak256(abi.encode(randomIndex + counter))) % signedOrders.length;
                continue;
            }
            signedOrdersFilled[randomIndex] = true;
            randomIndex = uint256(keccak256(abi.encode(randomIndex + counter))) % signedOrders.length;
            signedOrdersToFill[numOrdersChosen] = signedOrders[randomIndex].signedOrder;
            numOrdersChosen++;
        }
        console.log("FINISHED: length of signedOrdersToFill = ", signedOrdersToFill.length);
        console.log("*****END RUN*****");
    }

    function balancesAreCorrect() public returns (bool) {
        console.log("inside balancesAreCorrect()");
        console.log("1st check");
        if (tokenIn.balanceOf(address(fillContract)) != numOrdersFilled * ONE) {
            console.log("FALSE: tokenIn.balanceOf(address(fillContract)) != numOrdersFilled * ONE");
            return false;
        }
        console.log("2nd check");
        if (tokenOut.balanceOf(address(fillContract)) != (INITIAL_BALANCE - numOrdersFilled * ONE)) {
            console.log("FALSE: tokenOut.balanceOf(address(fillContract)) != (INITIAL_BALANCE - numOrdersFilled * ONE)");
            return false;
        }
        console.log("3rd check");
        if (tokenIn.balanceOf(maker1) != (INITIAL_BALANCE - numOrdersFilled * ONE)) {
            console.log("FALSE: tokenIn.balanceOf(maker1) != (INITIAL_BALANCE - numOrdersFilled * ONE)");
            return false;
        }
        console.log("4th check");
        if (tokenOut.balanceOf(maker1) != numOrdersFilled * ONE) {
            console.log("FALSE: tokenOut.balanceOf(maker1) != numOrdersFilled * ONE");
            return false;
        }
        console.log("done all checks!");
        return true;
    }
}

contract MultipleMakersInvariants is Test, InvariantTest, DeployPermit2 {
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
        //        assertTrue(true);
    }
}

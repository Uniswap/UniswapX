// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Solarray} from "solarray/Solarray.sol";
import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    DutchOrderReactor,
    DutchOrder,
    ResolvedOrder,
    DutchOutput,
    DutchInput,
    BaseReactor
} from "../../src/reactors/DutchOrderReactor.sol";
import {OrderInfo, InputToken, OutputToken, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import {DutchDecayLib} from "../../src/lib/DutchDecayLib.sol";
import {CurrencyLibrary} from "../../src/lib/CurrencyLibrary.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockDutchOrderReactor} from "../util/mock/MockDutchOrderReactor.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchOrder, DutchOrderLib} from "../../src/lib/DutchOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockFillContractWithOutputOverride} from "../util/mock/MockFillContractWithOutputOverride.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {BaseReactorTest} from "../base/BaseReactor.t.sol";

struct TestDutchOrderSpec {
    uint256 currentTime;
    uint256 startTime;
    uint256 endTime;
    uint256 deadline;
    DutchInput input;
    DutchOutput[] outputs;
}

// Base suite of tests for Dutch decay functionality
// Intended for extension of reactors that take Dutch style orders
abstract contract BaseDutchOrderReactorTest is PermitSignature, DeployPermit2, BaseReactorTest {
    using OrderInfoBuilder for OrderInfo;
    using DutchOrderLib for DutchOrder;

    OrderQuoter quoter;

    constructor() {
        quoter = new OrderQuoter();
    }

    /// @dev Create a signed order and return the order and orderHash
    /// @param request Order to sign
    function createAndSignDutchOrder(DutchOrder memory request)
        public
        virtual
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        orderHash = request.hash();
        return (SignedOrder(abi.encode(request), signOrder(swapperPrivateKey, address(permit2), request)), orderHash);
    }

    function generateOrder(TestDutchOrderSpec memory spec) private returns (SignedOrder memory order) {
        vm.warp(spec.currentTime);
        tokenIn.mint(address(swapper), uint256(spec.input.endAmount));
        tokenIn.forceApprove(swapper, address(permit2), spec.input.endAmount);

        DutchOrder memory request = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withDeadline(spec.deadline).withSwapper(address(swapper)),
            decayStartTime: spec.startTime,
            decayEndTime: spec.endTime,
            input: spec.input,
            outputs: spec.outputs
        });
        (order,) = createAndSignDutchOrder(request);
    }

    function test_dutch_resolveOutputNotStarted() public {
        uint256 currentTime = 1000;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime + 100,
                endTime: currentTime + 200,
                deadline: currentTime + 200,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 2000, 1000, address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 2000);
        assertEq(resolvedOrder.input.amount, 0);
    }

    function test_dutch_resolveOutputHalfwayDecayed() public {
        uint256 currentTime = 1000;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime - 100,
                endTime: currentTime + 100,
                deadline: currentTime + 200,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 2000, 1000, address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1500);
        assertEq(resolvedOrder.input.amount, 0);
    }

    function test_dutch_resolveOutputFullyDecayed() public {
        uint256 currentTime = 1000;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime - 200,
                endTime: currentTime - 100,
                deadline: currentTime + 200,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 2000, 1000, address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 0);
    }

    function test_dutch_resolveInputNotStarted() public {
        uint256 currentTime = 1000;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime + 100,
                endTime: currentTime + 200,
                deadline: currentTime + 200,
                input: DutchInput(tokenIn, 1000, 2000),
                outputs: OutputsBuilder.singleDutch(tokenOut, 0, 0, address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 1000);
    }

    function test_dutch_resolveInputHalfwayDecayed() public {
        uint256 currentTime = 1000;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime - 100,
                endTime: currentTime + 100,
                deadline: currentTime + 200,
                input: DutchInput(tokenIn, 1000, 2000),
                outputs: OutputsBuilder.singleDutch(tokenOut, 0, 0, address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 1500);
    }

    function test_dutch_resolveInputFullyDecayed() public {
        uint256 currentTime = 1000;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime - 200,
                endTime: currentTime - 100,
                deadline: currentTime + 200,
                input: DutchInput(tokenIn, 1000, 2000),
                outputs: OutputsBuilder.singleDutch(tokenOut, 0, 0, address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 2000);
    }

    // 1000 - (1000-900) * (1659087340-1659029740) / (1659130540-1659029740) = 943
    function test_dutch_resolveEndTimeAfterNow() public {
        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: 1659087340,
                startTime: 1659029740,
                endTime: 1659130540,
                deadline: 1659130540,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 1000, 900, address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 943);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
    }

    // Test multiple dutch outputs get resolved correctly. Use same time points as
    // testResolveEndTimeAfterNow().
    function test_dutch_resolveMultipleDutchOutputs() public {
        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: 1659087340,
                startTime: 1659029740,
                endTime: 1659130540,
                deadline: 1659130540,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.multipleDutch(
                    tokenOut, Solarray.uint256s(1000, 10000, 2000), Solarray.uint256s(900, 9000, 1000), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs.length, 3);
        assertEq(resolvedOrder.outputs[0].amount, 943);
        assertEq(resolvedOrder.outputs[1].amount, 9429);
        assertEq(resolvedOrder.outputs[2].amount, 1429);
        assertEq(resolvedOrder.input.amount, 0);
    }

    // Test that when decayStartTime = now, that the output = startAmount
    function test_dutch_resolveStartTimeEqualsNow() public {
        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: 1659029740,
                startTime: 1659029740,
                endTime: 1659130540,
                deadline: 1659130540,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 1000, 900, address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
    }

    // At time 1659030747, output will still be 1000. One second later at 1659030748,
    // the first decay will occur and the output will be 999.
    function test_dutch_resolveFirstDecay() public {
        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: 1659030747,
                startTime: 1659029740,
                endTime: 1659130540,
                deadline: 1659130540,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 1000, 900, address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);

        vm.warp(1659030748);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 999);
    }

    // startAmount is expected to always be greater than endAmount
    // otherwise the order decays out of favor for the swapper
    function test_dutch_resolveStartAmountLessThanEndAmount() public {
        uint256 currentTime = 100;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime,
                endTime: currentTime + 100,
                deadline: currentTime + 100,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 900, 1000, address(0))
            })
        );
        vm.expectRevert(DutchDecayLib.IncorrectAmounts.selector);
        quoter.quote(order.order, order.sig);
    }

    function test_dutch_validateDutchEndTimeBeforeStart() public {
        uint256 currentTime = 100;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime + 100,
                endTime: currentTime + 99,
                deadline: currentTime + 100,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 1000, 900, address(0))
            })
        );
        vm.expectRevert(DutchDecayLib.EndTimeBeforeStartTime.selector);
        quoter.quote(order.order, order.sig);
    }

    function test_dutch_validateDutchEndTimeEqualStart() public {
        uint256 currentTime = 100;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime + 100,
                endTime: currentTime + 100,
                deadline: currentTime + 100,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 1000, 900, address(0))
            })
        );
        vm.expectRevert(DutchDecayLib.EndTimeBeforeStartTime.selector);
        quoter.quote(order.order, order.sig);
    }

    function test_dutch_validateDutchEndTimeAfterStart() public {
        uint256 currentTime = 100;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime + 100,
                endTime: currentTime + 101,
                deadline: currentTime + 200,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 1000, 900, address(0))
            })
        );
        quoter.quote(order.order, order.sig);
    }

    function test_dutch_validateEndTimeAfterDeadline() public {
        uint256 currentTime = 100;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime,
                endTime: currentTime + 100,
                deadline: currentTime + 99,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, 1000, 900, address(0))
            })
        );
        vm.expectRevert(DutchOrderReactor.DeadlineBeforeEndTime.selector);
        quoter.quote(order.order, order.sig);
    }

    function test_dutch_validateInputDecayIncorrectAmounts() public {
        uint256 currentTime = 100;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime,
                endTime: currentTime + 100,
                deadline: currentTime + 100,
                input: DutchInput(tokenIn, 110, 100),
                outputs: OutputsBuilder.singleDutch(tokenOut, 1000, 1000, address(0))
            })
        );
        vm.expectRevert(DutchDecayLib.IncorrectAmounts.selector);
        quoter.quote(order.order, order.sig);
    }

    function test_dutch_validateOutputDecayIncorrectAmounts() public {
        uint256 currentTime = 100;

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: currentTime,
                startTime: currentTime,
                endTime: currentTime + 100,
                deadline: currentTime + 100,
                input: DutchInput(tokenIn, 100, 100),
                outputs: OutputsBuilder.singleDutch(tokenOut, 1000, 1100, address(0))
            })
        );
        vm.expectRevert(DutchDecayLib.IncorrectAmounts.selector);
        quoter.quote(order.order, order.sig);
    }

    function test_dutch_fuzzDecayNeverOutOfBounds(
        uint128 currentTime,
        uint128 decayStartTime,
        uint128 startAmount,
        uint128 decayEndTime,
        uint128 endAmount
    ) public {
        vm.assume(decayStartTime < decayEndTime);
        vm.assume(startAmount > endAmount);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentTime: uint256(currentTime),
                startTime: uint256(decayStartTime),
                endTime: uint256(decayEndTime),
                deadline: type(uint256).max,
                input: DutchInput(tokenIn, 0, 0),
                outputs: OutputsBuilder.singleDutch(tokenOut, uint256(startAmount), uint256(endAmount), address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertLe(resolvedOrder.outputs[0].amount, startAmount);
        assertGe(resolvedOrder.outputs[0].amount, endAmount);
    }
}

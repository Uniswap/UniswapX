// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {OrderInfo, InputToken, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {IReactor} from "../../src/interfaces/IReactor.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {DutchDecayLib} from "../../src/lib/DutchDecayLib.sol";
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockSwapper} from "../util/mock/users/MockSwapper.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockOrder} from "../util/mock/MockOrderStruct.sol";
import {LimitOrderReactor, LimitOrder} from "../../src/reactors/LimitOrderReactor.sol";
import {DutchOrderReactor, DutchOrder, DutchOutput, DutchInput} from "../../src/reactors/DutchOrderReactor.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract OrderQuoterTest is Test, PermitSignature, ReactorEvents, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;

    uint256 constant ONE = 10 ** 18;
    address constant PROTOCOL_FEE_OWNER = address(1);

    OrderQuoter quoter;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 swapperPrivateKey;
    address swapper;
    LimitOrderReactor limitOrderReactor;
    DutchOrderReactor dutchOrderReactor;
    IPermit2 permit2;

    function setUp() public {
        quoter = new OrderQuoter();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        tokenIn.mint(address(swapper), ONE);
        permit2 = IPermit2(deployPermit2());
        limitOrderReactor = new LimitOrderReactor(permit2, PROTOCOL_FEE_OWNER);
        dutchOrderReactor = new DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
    }

    function testQuoteLimitOrder() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withSwapper(address(swapper)),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);
        assertEq(address(quote.input.token), address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }

    function testQuoteDutchOrder() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withSwapper(address(swapper)),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: dutchOutputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);

        assertEq(address(quote.input.token), address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }

    function testQuoteDutchOrderAfterOutputDecay() public {
        vm.warp(block.timestamp + 100);
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withSwapper(address(swapper)),
            decayStartTime: block.timestamp - 100,
            decayEndTime: 201,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: dutchOutputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);

        assertEq(address(quote.input.token), address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE * 95 / 100);
    }

    function testQuoteDutchOrderAfterInputDecay() public {
        vm.warp(block.timestamp + 100);
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE, address(0));
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withSwapper(address(swapper)),
            decayStartTime: block.timestamp - 100,
            decayEndTime: 201,
            input: DutchInput(tokenIn, ONE * 9 / 10, ONE),
            outputs: dutchOutputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);

        assertEq(address(quote.input.token), address(tokenIn));
        assertEq(quote.input.amount, ONE * 95 / 100);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }

    function testQuoteLimitOrderDeadlinePassed() public {
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withSwapper(address(swapper)).withDeadline(
                block.timestamp - 1
                ),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert(ResolvedOrderLib.DeadlinePassed.selector);
        quoter.quote(abi.encode(order), sig);
    }

    function testQuoteLimitOrderInsufficientBalance() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withSwapper(address(swapper)),
            input: InputToken(tokenIn, ONE * 2, ONE * 2),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        quoter.quote(abi.encode(order), sig);
    }

    function testQuoteDutchOrderEndBeforeStart() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withSwapper(address(swapper)),
            decayStartTime: block.timestamp + 1000,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: dutchOutputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert(DutchDecayLib.EndTimeBeforeStartTime.selector);
        quoter.quote(abi.encode(order), sig);
    }

    function testGetReactorLimitOrder() public {
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(0x1234)),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        IReactor reactor = quoter.getReactor(abi.encode(order));
        assertEq(address(reactor), address(0x1234));
    }

    function testGetReactorDutchOrder() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(0x2345)),
            decayStartTime: block.timestamp + 1000,
            decayEndTime: block.timestamp + 1100,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: dutchOutputs
        });
        IReactor reactor = quoter.getReactor(abi.encode(order));
        assertEq(address(reactor), address(0x2345));
    }

    function testGetReactorMockOrder() public {
        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(0x3456)),
            mockField1: 0,
            mockField2: 0,
            mockField3: 0,
            mockField4: 0,
            mockField5: 0,
            mockField6: 0,
            mockField7: 0,
            mockField8: 0,
            mockField9: 0
        });
        IReactor reactor = quoter.getReactor(abi.encode(order));
        assertEq(address(reactor), address(0x3456));
    }
}

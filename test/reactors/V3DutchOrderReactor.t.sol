// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    V3DutchOrder,
    V3DutchOrderLib,
    CosignerData,
    V3DutchOrderReactor,
    ResolvedOrder,
    BaseReactor
} from "../../src/reactors/V3DutchOrderReactor.sol";
import {V3DutchOutput, V3DutchInput, NonlinearDutchDecay} from "../../src/lib/V3DutchOrderLib.sol";
import {Uint16Array, toUint256} from "../../src/types/Uint16Array.sol";
import {OrderInfo, InputToken, SignedOrder, OutputToken} from "../../src/base/ReactorStructs.sol";
import {ExclusivityLib} from "../../src/lib/ExclusivityLib.sol";
import {DutchDecayLib} from "../../src/lib/DutchDecayLib.sol";
import {CurrencyLibrary, NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockFillContractWithOutputOverride} from "../util/mock/MockFillContractWithOutputOverride.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {BaseReactorTest} from "../base/BaseReactor.t.sol";
import {CurveBuilder} from "../util/CurveBuilder.sol";

contract V3DutchOrderTest is PermitSignature, DeployPermit2, BaseReactorTest {
    using OrderInfoBuilder for OrderInfo;
    using V3DutchOrderLib for V3DutchOrder;

    uint256 constant cosignerPrivateKey = 0x99999999;

    function name() public pure override returns (string memory) {
        return "V3DutchOrder";
    }

    function createReactor() public override returns (BaseReactor) {
        return new V3DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
    }

    /// @dev Create and return a basic single Dutch limit order along with its signature, orderHash, and orderInfo
    function createAndSignOrder(ResolvedOrder memory request)
        public
        view
        override
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        V3DutchOutput[] memory outputs = new V3DutchOutput[](request.outputs.length);
        for (uint256 i = 0; i < request.outputs.length; i++) {
            OutputToken memory output = request.outputs[i];
            outputs[i] = V3DutchOutput({
                token: output.token,
                startAmount: output.amount,
                curve: CurveBuilder.emptyCurve(),
                recipient: output.recipient
            });
        }

        uint256[] memory outputAmounts = new uint256[](request.outputs.length);
        for (uint256 i = 0; i < request.outputs.length; i++) {
            outputAmounts[i] = 0;
        }

        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: outputAmounts
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: request.info,
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(
                request.input.token, request.input.amount, CurveBuilder.emptyCurve(), request.input.amount
            ),
            baseOutputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        orderHash = order.hash();
        order.cosignature = cosignOrder(orderHash, cosignerData);
        return (SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)), orderHash);
    }

    function testWrongCosigner() public {
        address wrongCosigner = makeAddr("wrongCosigner");
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 1 ether,
            outputAmounts: ArrayBuilder.fill(1, 1 ether)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: wrongCosigner,
            baseInput: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 1 ether, 1 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V3DutchOrderReactor.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    function testInvalidCosignature() public {
        address wrongCosigner = makeAddr("wrongCosigner");
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 1 ether,
            outputAmounts: ArrayBuilder.fill(1, 1 ether)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: wrongCosigner,
            baseInput: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 1 ether, 1 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = bytes.concat(keccak256("invalidSignature"), keccak256("invalidSignature"), hex"33");
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V3DutchOrderReactor.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    function testInputOverrideWorse() public {
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            // override is more input tokens than expected
            inputAmount: 0.9 ether,
            outputAmounts: ArrayBuilder.fill(1, 1.1 ether)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(tokenIn, 0.8 ether, CurveBuilder.emptyCurve(), 1 ether),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 1 ether, 1 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V3DutchOrderReactor.InvalidCosignerInput.selector);
        fillContract.execute(signedOrder);
    }

    function testOutputOverrideWorse() public {
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            // override is more input tokens than expected
            inputAmount: 1 ether,
            outputAmounts: ArrayBuilder.fill(1, 0.9 ether)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 1 ether, 0.8 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V3DutchOrderReactor.InvalidCosignerOutput.selector);
        fillContract.execute(signedOrder);
    }

    function testOutputOverrideWrongLength() public {
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            // override is more input tokens than expected
            inputAmount: 1 ether,
            outputAmounts: ArrayBuilder.fill(2, 1.1 ether)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 1 ether, 0.8 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V3DutchOrderReactor.InvalidCosignerOutput.selector);
        fillContract.execute(signedOrder);
    }

    function testOverrideInput() public {
        uint256 outputAmount = 1 ether;
        uint256 overriddenInputAmount = 0.7 ether;
        tokenIn.mint(swapper, overriddenInputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: overriddenInputAmount,
            outputAmounts: ArrayBuilder.fill(1, 0)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(tokenIn, 0.8 ether, CurveBuilder.emptyCurve(), 1 ether),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), outputAmount, outputAmount, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        _snapStart("V3-InputOverride");
        fillContract.execute(signedOrder);
        snapEnd();

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), overriddenInputAmount);
    }

    function testOverrideOutput() public {
        uint256 overriddenOutputAmount = 1.1 ether;
        uint256 inputAmount = 1 ether;
        tokenIn.mint(swapper, inputAmount);
        tokenOut.mint(address(fillContract), overriddenOutputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, overriddenOutputAmount)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(tokenIn, inputAmount, CurveBuilder.emptyCurve(), inputAmount),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 1 ether, 0.9 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        _snapStart("V3-OutputOverride");
        fillContract.execute(signedOrder);
        snapEnd();

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenOut.balanceOf(swapper), overriddenOutputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    function testStrictExclusivityInvalidCaller() public {
        uint256 inputAmount = 1 ether;
        tokenIn.mint(swapper, inputAmount);
        tokenOut.mint(address(fillContract), inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(1),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, 0)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(tokenIn, inputAmount, CurveBuilder.emptyCurve(), inputAmount),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 1 ether, 0.9 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(ExclusivityLib.NoExclusiveOverride.selector);
        fillContract.execute(signedOrder);
    }

    function testStrictExclusivityValidCaller() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        tokenIn.mint(swapper, inputAmount);
        tokenOut.mint(address(fillContract), inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(fillContract),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, 0)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(tokenIn, inputAmount, CurveBuilder.emptyCurve(), inputAmount),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), outputAmount, 0.9 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.prank(address(1));

        _snapStart("V3-ExclusiveFiller");
        fillContract.execute(signedOrder);
        snapEnd();

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    function testExclusiveOverrideInvalidCallerCosignedAmountOutput() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 exclusivityOverrideBps = 10;
        tokenIn.mint(swapper, inputAmount);
        tokenOut.mint(address(fillContract), outputAmount * 2);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(1),
            exclusivityOverrideBps: exclusivityOverrideBps,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, outputAmount)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(tokenIn, inputAmount, CurveBuilder.emptyCurve(), inputAmount),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 1 ether, 0.9 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        fillContract.execute(signedOrder);
        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenOut.balanceOf(swapper), outputAmount * (10000 + exclusivityOverrideBps) / 10000);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    function testExclusiveOverrideInvalidCallerNoCosignedAmountOutput() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 exclusivityOverrideBps = 10;
        tokenIn.mint(swapper, inputAmount);
        tokenOut.mint(address(fillContract), outputAmount * 2);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(1),
            exclusivityOverrideBps: exclusivityOverrideBps,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, 0)
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(tokenIn, inputAmount, CurveBuilder.emptyCurve(), inputAmount),
            baseOutputs: OutputsBuilder.singleV3Dutch(address(tokenOut), outputAmount, 0.9 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        fillContract.execute(signedOrder);
        assertEq(tokenIn.balanceOf(swapper), 0);
        // still overrides the base swapper signed amount
        assertEq(tokenOut.balanceOf(swapper), outputAmount * (10000 + exclusivityOverrideBps) / 10000);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    // function testExecuteInputAndOutputDecay() public {
    //     uint256 inputAmount = 1 ether;
    //     uint256 outputAmount = 1 ether;
    //     uint256 startTime = block.timestamp;
    //     uint256 deadline = startTime + 1000;
    //     // Seed both swapper and fillContract with enough tokens (important for dutch order)
    //     tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
    //     tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
    //     tokenIn.forceApprove(swapper, address(permit2), inputAmount);

    //     SignedOrder memory order = generateOrder(
    //         TestDutchOrderSpec({
    //             currentTime: startTime,
    //             startTime: startTime,
    //             endTime: deadline,
    //             deadline: deadline,
    //             input: V3DutchInput(tokenIn, inputAmount, inputAmount * 110 / 100),
    //             outputs: OutputsBuilder.singleV3Dutch(tokenOut, outputAmount, outputAmount * 90 / 100, address(swapper))
    //         })
    //     );
    //     uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
    //     uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));
    //     vm.expectEmit(false, true, true, false, address(reactor));
    //     emit Fill(keccak256("not checked"), address(fillContract), swapper, 0);
    //     vm.warp(startTime + 500);
    //     fillContract.execute(order);
    //     uint256 swapperInputBalanceEnd = tokenIn.balanceOf(address(swapper));
    //     uint256 swapperOutputBalanceEnd = tokenOut.balanceOf(address(swapper));
    //     assertEq(swapperInputBalanceStart - swapperInputBalanceEnd, inputAmount * 105 / 100);
    //     assertEq(swapperOutputBalanceEnd - swapperOutputBalanceStart, outputAmount * 95 / 100);
    // }

    function cosignOrder(bytes32 orderHash, CosignerData memory cosignerData) private pure returns (bytes memory sig) {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        sig = bytes.concat(r, s, bytes1(v));
    }

    function generateSignedOrders(V3DutchOrder[] memory orders) private view returns (SignedOrder[] memory result) {
        result = new SignedOrder[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            bytes memory sig = signOrder(swapperPrivateKey, address(permit2), orders[i]);
            result[i] = SignedOrder(abi.encode(orders[i]), sig);
        }
    }
}

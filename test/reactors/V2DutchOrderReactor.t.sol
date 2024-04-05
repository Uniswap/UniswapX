// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    V2DutchOrder,
    V2DutchOrderLib,
    CosignerData,
    V2DutchOrderReactor,
    ResolvedOrder,
    DutchOutput,
    DutchInput,
    BaseReactor
} from "../../src/reactors/V2DutchOrderReactor.sol";
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
import {DutchOrder, BaseDutchOrderReactorTest} from "./BaseDutchOrderReactor.t.sol";

contract V2DutchOrderTest is PermitSignature, DeployPermit2, BaseDutchOrderReactorTest {
    using OrderInfoBuilder for OrderInfo;
    using V2DutchOrderLib for V2DutchOrder;

    uint256 constant cosignerPrivateKey = 0x99999999;

    function name() public pure override returns (string memory) {
        return "V2DutchOrder";
    }

    function createReactor() public override returns (BaseReactor) {
        return new V2DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
    }

    /// @dev Create and return a basic single Dutch limit order along with its signature, orderHash, and orderInfo
    function createAndSignOrder(ResolvedOrder memory request)
        public
        view
        override
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        DutchOutput[] memory outputs = new DutchOutput[](request.outputs.length);
        for (uint256 i = 0; i < request.outputs.length; i++) {
            OutputToken memory output = request.outputs[i];
            outputs[i] = DutchOutput({
                token: output.token,
                startAmount: output.amount,
                endAmount: output.amount,
                recipient: output.recipient
            });
        }

        uint256[] memory outputAmounts = new uint256[](request.outputs.length);
        for (uint256 i = 0; i < request.outputs.length; i++) {
            outputAmounts[i] = 0;
        }

        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: request.info.deadline,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: outputAmounts
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: request.info,
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(request.input.token, request.input.amount, request.input.amount),
            baseOutputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        orderHash = order.hash();
        order.cosignature = cosignOrder(orderHash, cosignerData);
        return (SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)), orderHash);
    }

    /// @dev Create a signed order and return the order and orderHash
    /// @param request Order to sign
    function createAndSignDutchOrder(DutchOrder memory request)
        public
        view
        override
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        uint256[] memory outputAmounts = new uint256[](request.outputs.length);
        for (uint256 i = 0; i < request.outputs.length; i++) {
            outputAmounts[i] = 0;
        }
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: request.decayStartTime,
            decayEndTime: request.decayEndTime,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: outputAmounts
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: request.info,
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: request.input,
            baseOutputs: request.outputs,
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
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 1 ether,
            outputAmounts: ArrayBuilder.fill(1, 1 ether)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: wrongCosigner,
            baseInput: DutchInput(tokenIn, 1 ether, 1 ether),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 1 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V2DutchOrderReactor.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    function testInvalidCosignature() public {
        address wrongCosigner = makeAddr("wrongCosigner");
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 1 ether,
            outputAmounts: ArrayBuilder.fill(1, 1 ether)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: wrongCosigner,
            baseInput: DutchInput(tokenIn, 1 ether, 1 ether),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 1 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = bytes.concat(keccak256("invalidSignature"), keccak256("invalidSignature"), hex"33");
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V2DutchOrderReactor.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    function testInputOverrideWorse() public {
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            // override is more input tokens than expected
            inputAmount: 0.9 ether,
            outputAmounts: ArrayBuilder.fill(1, 1.1 ether)
        });
        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(tokenIn, 0.8 ether, 1 ether),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 1 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V2DutchOrderReactor.InvalidCosignerInput.selector);
        fillContract.execute(signedOrder);
    }

    function testOutputOverrideWorse() public {
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            // override is more input tokens than expected
            inputAmount: 1 ether,
            outputAmounts: ArrayBuilder.fill(1, 0.9 ether)
        });
        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(tokenIn, 1 ether, 1 ether),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 0.8 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V2DutchOrderReactor.InvalidCosignerOutput.selector);
        fillContract.execute(signedOrder);
    }

    function testOutputOverrideWrongLength() public {
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            // override is more input tokens than expected
            inputAmount: 1 ether,
            outputAmounts: ArrayBuilder.fill(2, 1.1 ether)
        });
        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(tokenIn, 1 ether, 1 ether),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 0.8 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V2DutchOrderReactor.InvalidCosignerOutput.selector);
        fillContract.execute(signedOrder);
    }

    function testOverrideInput() public {
        uint256 outputAmount = 1 ether;
        uint256 overriddenInputAmount = 0.7 ether;
        tokenIn.mint(swapper, overriddenInputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: overriddenInputAmount,
            outputAmounts: ArrayBuilder.fill(1, 0)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(tokenIn, 0.8 ether, 1 ether),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        _snapStart("InputOverride");
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
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, overriddenOutputAmount)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(tokenIn, inputAmount, inputAmount),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 0.9 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        _snapStart("OutputOverride");
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
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(1),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, 0)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(tokenIn, inputAmount, inputAmount),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 0.9 ether, swapper),
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
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(fillContract),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, 0)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(tokenIn, inputAmount, inputAmount),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, 0.9 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.prank(address(1));

        _snapStart("ExclusiveFiller");
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
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(1),
            exclusivityOverrideBps: exclusivityOverrideBps,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, outputAmount)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(tokenIn, inputAmount, inputAmount),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 0.9 ether, swapper),
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
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(1),
            exclusivityOverrideBps: exclusivityOverrideBps,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, 0)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(tokenIn, inputAmount, inputAmount),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, 0.9 ether, swapper),
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

    function cosignOrder(bytes32 orderHash, CosignerData memory cosignerData) private pure returns (bytes memory sig) {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        sig = bytes.concat(r, s, bytes1(v));
    }

    function generateSignedOrders(V2DutchOrder[] memory orders) private view returns (SignedOrder[] memory result) {
        result = new SignedOrder[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            bytes memory sig = signOrder(swapperPrivateKey, address(permit2), orders[i]);
            result[i] = SignedOrder(abi.encode(orders[i]), sig);
        }
    }
}

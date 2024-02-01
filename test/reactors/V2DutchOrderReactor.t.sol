// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    V2DutchOrder,
    V2DutchOrderLib,
    CosignerExtraDataLib,
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
    using CosignerExtraDataLib for bytes;

    uint256 constant cosignerPrivateKey = 0x99999999;

    uint256[] internal NO_OUTPUT_OVERRIDES = new uint256[](0);

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

        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: request.info.deadline,
            extraData: encodeExtraCosignerData(address(0), 0, NO_OUTPUT_OVERRIDES)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: request.info,
            cosigner: vm.addr(cosignerPrivateKey),
            input: DutchInput(request.input.token, request.input.amount, request.input.amount),
            outputs: outputs,
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
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: request.decayStartTime,
            decayEndTime: request.decayEndTime,
            extraData: encodeExtraCosignerData(address(0), 0, NO_OUTPUT_OVERRIDES)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: request.info,
            cosigner: vm.addr(cosignerPrivateKey),
            input: request.input,
            outputs: request.outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });

        orderHash = order.hash();
        order.cosignature = cosignOrder(orderHash, cosignerData);
        return (SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)), orderHash);
    }

    function testInvalidCosignature() public {
        address wrongCosigner = makeAddr("wrongCosigner");
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            extraData: encodeExtraCosignerData(address(0), 1 ether, ArrayBuilder.fill(1, 1 ether))
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: wrongCosigner,
            input: DutchInput(tokenIn, 1 ether, 1 ether),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 1 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V2DutchOrderReactor.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    function testInputOverrideWorse() public {
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            extraData: encodeExtraCosignerData(address(0), 0.9 ether, ArrayBuilder.fill(1, 1.1 ether))
        });
        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            input: DutchInput(tokenIn, 0.8 ether, 1 ether),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 1 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V2DutchOrderReactor.InvalidInputOverride.selector);
        fillContract.execute(signedOrder);
    }

    function testOutputOverrideWorse() public {
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            extraData: encodeExtraCosignerData(address(0), 1 ether, ArrayBuilder.fill(1, 0.9 ether))
        });
        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            input: DutchInput(tokenIn, 1 ether, 1 ether),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 0.8 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V2DutchOrderReactor.InvalidOutputOverride.selector);
        fillContract.execute(signedOrder);
    }

    function testOutputOverrideWrongLength() public {
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            extraData: encodeExtraCosignerData(address(0), 1 ether, ArrayBuilder.fill(2, 1.1 ether))
        });
        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            input: DutchInput(tokenIn, 1 ether, 1 ether),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 0.8 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V2DutchOrderReactor.InvalidOutputOverride.selector);
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
            extraData: encodeExtraCosignerData(address(0), overriddenInputAmount, NO_OUTPUT_OVERRIDES)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            input: DutchInput(tokenIn, 0.8 ether, 1 ether),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        fillContract.execute(signedOrder);
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
            extraData: encodeExtraCosignerData(address(0), 0, ArrayBuilder.fill(1, overriddenOutputAmount))
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 0.9 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        fillContract.execute(signedOrder);
        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenOut.balanceOf(swapper), overriddenOutputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    function testEncoding() public {
        bytes memory encodedBytes = encodeExtraCosignerData(address(1111111111111111), 22222222222222, ArrayBuilder.fill(3, 5));
        assertTrue(encodedBytes.hasExclusiveFiller());
        assertTrue(encodedBytes.hasInputOverride());
        assertTrue(encodedBytes.hasOutputOverrides());
        (address filler, uint256 input, uint256[] memory output) = encodedBytes.decodeExtraParameters();
        assertEq(filler, address(1111111111111111));
        assertEq(input, 22222222222222);
        assertEq(output.length, 3);
        assertEq(output[0], 5);
        assertEq(output[1], 5);
        assertEq(output[2], 5);
    }

    function testExclusivity() public {
        uint256 inputAmount = 1 ether;
        tokenIn.mint(swapper, inputAmount);
        tokenOut.mint(address(fillContract), inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        CosignerData memory cosignerData = CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            extraData: encodeExtraCosignerData(address(1), 0, NO_OUTPUT_OVERRIDES)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper),
            cosigner: vm.addr(cosignerPrivateKey),
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), 1 ether, 0.9 ether, swapper),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(ExclusivityLib.NoExclusiveOverride.selector);
        fillContract.execute(signedOrder);
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

    function encodeExtraCosignerData(address exclusiveFiller, uint256 inputOverride, uint256[] memory outputOverrides)
        private
        pure
        returns (bytes memory extraData)
    {
        bool hasExclusiveFiller = (exclusiveFiller != address(0));
        bool hasInputOverride = (inputOverride != 0);
        bool hasOutputOverrides = (outputOverrides.length != 0);

        bytes1 firstByte = 0x00;
        if (hasExclusiveFiller) firstByte |= 0x80;
        if (hasInputOverride) firstByte |= 0x40;
        if (hasOutputOverrides) firstByte |= 0x20;

        if (firstByte == 0x00) return "";

        extraData = abi.encodePacked(firstByte);
        if (hasExclusiveFiller) extraData = bytes.concat(extraData, abi.encodePacked(exclusiveFiller));
        if (hasInputOverride) extraData = bytes.concat(extraData, abi.encodePacked(inputOverride));
        if (hasOutputOverrides) {
            extraData = bytes.concat(extraData, abi.encodePacked(outputOverrides.length));
            extraData = bytes.concat(extraData, abi.encodePacked(outputOverrides));
        }
    }
}

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {V3DutchOrder, V3DutchOrderLib, CosignerData, V3DutchOrderReactor, ResolvedOrder, BaseReactor} from "../../src/reactors/V3DutchOrderReactor.sol";
import {OrderInfo, InputToken, SignedOrder, OutputToken} from "../../src/base/ReactorStructs.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {V3DutchOutput, V3DutchInput, NonlinearDutchDecay} from "../../src/lib/V3DutchOrderLib.sol";
import {CurveBuilder} from "../util/CurveBuilder.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {CosignerLib} from "../../src/lib/CosignerLib.sol";
import {IReactor} from "../../src/interfaces/IReactor.sol";
import {IValidationCallback} from "../../src/interfaces/IValidationCallback.sol";
import {OrderInfoLib} from "../../src/lib/OrderInfoLib.sol";

contract V3DutchOrderHashingTest is Test {
    using V3DutchOrderLib for V3DutchOrder;

    function testV3DutchOrderHashing() public {
        // V3DutchOrder memory order = createSampleOrder();
        // console.log("Full Order:");
        // logOrder(order); //Make sure it's what I expect
        // //Hash the thing
        // vm.breakpoint("a");
        // bytes memory encodedOrder = abi.encode(order, V3DutchOrderLib.ORDER_TYPE_HASH);
        // console.log(vm.toString(encodedOrder));
        // V3DutchOrder memory decodedOrder = abi.decode(encodedOrder, (V3DutchOrder));
        // console.log("Decoded Order:");
        // logOrder(decodedOrder);
        bytes memory encodedSDKOrder = hex"";
        V3DutchOrder memory decodedSDKOrder = abi.decode(encodedSDKOrder, (V3DutchOrder));
        console.log("Decoded SDK Order:");
        logOrder(decodedSDKOrder);
        bytes32 orderHash = decodedSDKOrder.hash();
        console.log("preimage:");
        console.log(vm.toString(V3DutchOrderLib.ORDER_TYPE_HASH));
        console.log("Order Hash:");
        console.log(vm.toString(orderHash));

        bytes32 cosignerDigest = decodedSDKOrder.cosignerDigest(orderHash);
        console.log("Cosigner Digest:");
        console.log(vm.toString(cosignerDigest));


        console.log("Solidity V3DutchOrder encoding:", vm.toString(abi.encode(
            V3DutchOrderLib.ORDER_TYPE_HASH,
            OrderInfoLib.hash(decodedSDKOrder.info),
            decodedSDKOrder.cosigner,
            decodedSDKOrder.startingBaseFee,
            V3DutchOrderLib.hash(decodedSDKOrder.baseInput),
            V3DutchOrderLib.hash(decodedSDKOrder.baseOutputs)
        )));
    }

    function createSampleOrder() internal returns (V3DutchOrder memory) {
        MockERC20 tokenIn = new MockERC20("Input", "IN", 18);
        MockERC20 tokenOut = new MockERC20("Output", "OUT", 18);

        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: 260000000,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            // override is more input tokens than expected
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, 0)
        });

        V3DutchOutput[] memory outputs = new V3DutchOutput[](1);
        outputs[0] = V3DutchOutput({
            token: address(0),
            startAmount: 0,
            curve: CurveBuilder.emptyCurve(),
            recipient: address(0),
            minAmount: 0,
            adjustmentPerGweiBaseFee: 0
        });
        OrderInfo memory testInfo = OrderInfo({
            reactor: IReactor(address(0)),
            swapper: address(0),
            nonce: 0,
            deadline: 1800000000,
            additionalValidationContract: IValidationCallback(address(0)),
            additionalValidationData: bytes("")
        });

        V3DutchOrder memory order = V3DutchOrder({
            // info: OrderInfoBuilder.init(address(0)),
            info: testInfo,
            cosigner: address(0),
            baseInput: V3DutchInput(
                tokenIn,
                21,
                CurveBuilder.singlePointCurve(1, 0),
                21,
                0
            ),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(0),
                21,
                20,
                CurveBuilder.singlePointCurve(1, 1),
                address(0)
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: 0
        });
        console.log(address(tokenIn));
        return order;
    }

    function logOrder(V3DutchOrder memory order) internal view {
        console.log("Order Info:");
        console.log("  Reactor:", address(order.info.reactor));
        console.log("  Swapper:", order.info.swapper);
        console.log("  Nonce:", order.info.nonce);
        console.log("  deadline:", order.info.deadline);
        console.log("  additionalValidationContract:", address(order.info.additionalValidationContract));
        console.log("  additionalValidationData:", vm.toString(order.info.additionalValidationData));


        console.log("Base Input:");
        console.log("  Token:", address(order.baseInput.token));
        console.log("  Start Amount:", order.baseInput.startAmount);
        console.log("  Curve, RelativeBlocks:", order.baseInput.curve.relativeBlocks);
        for (uint i = 0; i < order.baseInput.curve.relativeAmounts.length; i++) {
            console.log("  Curve, RelativeAmounts:", order.baseInput.curve.relativeAmounts[i]);
        }
        console.log("  Max Amount:", order.baseInput.maxAmount);
        console.log("  adjustmentPerGweiBaseFee:", order.baseInput.adjustmentPerGweiBaseFee);

        console.log("Base Outputs:");
        for (uint i = 0; i < order.baseOutputs.length; i++) {
            console.log("  Output", i);
            console.log("    Token:", order.baseOutputs[i].token);
            console.log("    Start Amount:", order.baseOutputs[i].startAmount);
            console.log("  Curve, RelativeBlocks:", order.baseInput.curve.relativeBlocks);
            for (uint j = 0; j < order.baseOutputs[i].curve.relativeAmounts.length;j++) {
                console.log("  Curve, RelativeAmounts:", order.baseOutputs[i].curve.relativeAmounts[j]);
            }
            console.log("    Recipient:", order.baseOutputs[i].recipient);
            console.log("    minAmount:", order.baseOutputs[i].minAmount);
            console.log("    adjustmentPerGweiBaseFee:", order.baseOutputs[i].adjustmentPerGweiBaseFee);
        }
        console.log("Cosigner Data:");
        console.log("  decayStartBlock:", order.cosignerData.decayStartBlock);
        console.log("  exclusiveFiller:", order.cosignerData.exclusiveFiller);
        console.log("  exclusivityOverrideBps:", order.cosignerData.exclusivityOverrideBps);
        console.log("  inputAmount:", order.cosignerData.inputAmount);
        for (uint i = 0; i < order.cosignerData.outputAmounts.length; i++) {
            console.log("  outputAmounts:", order.cosignerData.outputAmounts[i]);
        }
        console.log("Cosignature:", vm.toString(order.cosignature));
        console.log("Cosigner:", order.cosigner);
    }
}

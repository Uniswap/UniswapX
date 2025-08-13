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
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import {Solarray} from "solarray/Solarray.sol";
import {MathExt} from "../../src/lib/MathExt.sol";
import {CosignerLib} from "../../src/lib/CosignerLib.sol";

contract V3DutchOrderTest is PermitSignature, DeployPermit2, BaseReactorTest {
    using OrderInfoBuilder for OrderInfo;
    using V3DutchOrderLib for V3DutchOrder;

    OrderQuoter quoter;

    using MathExt for uint256;

    constructor() {
        quoter = new OrderQuoter();
    }

    uint256 constant cosignerPrivateKey = 0x99999999;

    function name() public pure override returns (string memory) {
        return "V3DutchOrder";
    }

    function createReactor() public override returns (BaseReactor) {
        return new V3DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
    }

    /// @dev Create and return a basic single Dutch limit order along with its signature, orderHash, and orderInfo
    function signAndEncodeOrder(ResolvedOrder memory request)
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
                recipient: output.recipient,
                minAmount: output.amount,
                adjustmentPerGweiBaseFee: 0
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
                request.input.token, request.input.amount, CurveBuilder.emptyCurve(), request.input.amount, 0
            ),
            baseOutputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        orderHash = order.hash();
        order.cosignature = cosignOrder(orderHash, cosignerData);
        return (SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)), orderHash);
    }

    /* Cosigner tests */

    function testV3InputOverrideWorse() public {
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
            baseInput: V3DutchInput(tokenIn, 0.8 ether, CurveBuilder.emptyCurve(), 1 ether, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), 1 ether, 1 ether, CurveBuilder.singlePointCurve(1, 0 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V3DutchOrderReactor.InvalidCosignerInput.selector);
        fillContract.execute(signedOrder);
    }

    function testV3OutputOverrideWorse() public {
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
            baseInput: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), 1 ether, 0.8 ether, CurveBuilder.singlePointCurve(1, 0.2 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V3DutchOrderReactor.InvalidCosignerOutput.selector);
        fillContract.execute(signedOrder);
    }

    function testV3OutputOverrideWrongLength() public {
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
            baseInput: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), 1 ether, 0.8 ether, CurveBuilder.singlePointCurve(1, 0.2 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(V3DutchOrderReactor.InvalidCosignerOutput.selector);
        fillContract.execute(signedOrder);
    }

    function testV3OverrideInput() public {
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
            baseInput: V3DutchInput(tokenIn, 0.8 ether, CurveBuilder.emptyCurve(), 1 ether, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), outputAmount, outputAmount, CurveBuilder.singlePointCurve(1, 0 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("V3-InputOverride");

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), overriddenInputAmount);
    }

    function testV3OverrideOutput() public {
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
            baseInput: V3DutchInput(tokenIn, inputAmount, CurveBuilder.emptyCurve(), inputAmount, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), 1 ether, 0.9 ether, CurveBuilder.singlePointCurve(1, 0.1 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("V3-OutputOverride");

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenOut.balanceOf(swapper), overriddenOutputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    function testV3StrictExclusivityInvalidCaller() public {
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
            baseInput: V3DutchInput(tokenIn, inputAmount, CurveBuilder.emptyCurve(), inputAmount, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), 1 ether, 0.9 ether, CurveBuilder.singlePointCurve(1, 0.1 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(ExclusivityLib.NoExclusiveOverride.selector);
        fillContract.execute(signedOrder);
    }

    function testV3StrictExclusivityValidCaller() public {
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
            baseInput: V3DutchInput(tokenIn, inputAmount, CurveBuilder.emptyCurve(), inputAmount, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), 1 ether, 0.9 ether, CurveBuilder.singlePointCurve(1, 0.1 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.prank(address(1));

        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("V3-ExclusiveFiller");

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    function testV3AppliesExclusiveOverride() public {
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
            baseInput: V3DutchInput(tokenIn, inputAmount, CurveBuilder.emptyCurve(), inputAmount, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), 1 ether, 0.9 ether, CurveBuilder.singlePointCurve(1, 0.1 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        fillContract.execute(signedOrder);
        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenOut.balanceOf(swapper), outputAmount * (10000 + exclusivityOverrideBps) / 10000);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    function testV3ExclusiveOverrideInvalidCallerNoCosignedAmountOutput() public {
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
            baseInput: V3DutchInput(tokenIn, inputAmount, CurveBuilder.emptyCurve(), inputAmount, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), 1 ether, 0.9 ether, CurveBuilder.singlePointCurve(1, 0.1 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
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

    /* Validation tests */

    function testV3WrongCosigner() public {
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
            baseInput: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), 1 ether, 1 ether, CurveBuilder.singlePointCurve(1, 0 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(CosignerLib.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    function testV3InvalidCosignature() public {
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
            baseInput: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), 1 ether, 1 ether, CurveBuilder.singlePointCurve(1, 0 ether), swapper
            ),
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        order.cosignature = bytes.concat(keccak256("invalidSignature"), keccak256("invalidSignature"), hex"33");
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
        vm.expectRevert(CosignerLib.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    function testV3ExecutePastDeadline() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 startBlock = block.number;
        uint256 deadline = block.timestamp + 1000;
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: block.number,
                startBlock: startBlock,
                deadline: deadline,
                input: V3DutchInput(
                    tokenIn,
                    inputAmount,
                    CurveBuilder.singlePointCurve(1000, 0 - int256(inputAmount * 10 / 100)),
                    inputAmount * 110 / 100,
                    0
                ),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut),
                    outputAmount,
                    outputAmount * 90 / 100,
                    CurveBuilder.singlePointCurve(1000, int256(outputAmount * 10 / 100)),
                    address(swapper)
                )
            })
        );
        vm.warp(deadline + 1);
        vm.expectRevert(V3DutchOrderReactor.DeadlineReached.selector);
        fillContract.execute(order);
    }

    /* Block decay tests */

    function testV3ExecuteInputAndOutputHalfDecay() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 startBlock = block.number;
        uint256 deadline = block.timestamp + 1000;
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: block.number,
                startBlock: startBlock,
                deadline: deadline,
                input: V3DutchInput(
                    tokenIn,
                    inputAmount,
                    CurveBuilder.singlePointCurve(1000, 0 - int256(inputAmount * 10 / 100)),
                    inputAmount * 110 / 100,
                    0
                ),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut),
                    outputAmount,
                    outputAmount * 90 / 100,
                    CurveBuilder.singlePointCurve(1000, int256(inputAmount * 10 / 100)),
                    address(swapper)
                )
            })
        );
        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));
        vm.expectEmit(false, true, true, false, address(reactor));
        emit Fill(keccak256("not checked"), address(fillContract), swapper, 0);
        vm.roll(startBlock + 500);
        fillContract.execute(order);
        uint256 swapperInputBalanceEnd = tokenIn.balanceOf(address(swapper));
        uint256 swapperOutputBalanceEnd = tokenOut.balanceOf(address(swapper));
        assertEq(swapperInputBalanceStart - swapperInputBalanceEnd, inputAmount * 105 / 100);
        assertEq(swapperOutputBalanceEnd - swapperOutputBalanceStart, outputAmount * 95 / 100);
    }

    function testV3ExecuteInputAndOutputFullDecay() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 startBlock = block.number;
        uint256 deadline = block.timestamp + 1000;
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: block.number,
                startBlock: startBlock,
                deadline: deadline,
                input: V3DutchInput(
                    tokenIn,
                    inputAmount,
                    CurveBuilder.singlePointCurve(1000, 0 - int256(inputAmount * 10 / 100)),
                    inputAmount * 110 / 100,
                    0
                ),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut),
                    outputAmount,
                    outputAmount * 90 / 100,
                    CurveBuilder.singlePointCurve(1000, int256(outputAmount * 10 / 100)),
                    address(swapper)
                )
            })
        );
        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));
        vm.expectEmit(false, true, true, false, address(reactor));
        emit Fill(keccak256("not checked"), address(fillContract), swapper, 0);
        vm.roll(startBlock + 1000);
        fillContract.execute(order);
        uint256 swapperInputBalanceEnd = tokenIn.balanceOf(address(swapper));
        uint256 swapperOutputBalanceEnd = tokenOut.balanceOf(address(swapper));
        assertEq(swapperInputBalanceStart - swapperInputBalanceEnd, inputAmount * 110 / 100);
        assertEq(swapperOutputBalanceEnd - swapperOutputBalanceStart, outputAmount * 90 / 100);
    }

    function testV3ResolveNotStarted() public {
        uint256 currentBlock = 1000;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: currentBlock + 100,
                deadline: currentBlock + 200,
                input: V3DutchInput(tokenIn, 1000, CurveBuilder.singlePointCurve(200, 1000), 2000, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 0, 0, CurveBuilder.singlePointCurve(200, -100), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 1000);
    }

    function testV3ResolveOutputHalfwayDecayed() public {
        uint256 currentBlock = 1000;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: currentBlock - 100,
                deadline: currentBlock + 200,
                input: V3DutchInput(tokenIn, 0, CurveBuilder.singlePointCurve(100, 0), 0, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 2000, 1000, CurveBuilder.singlePointCurve(200, 1000), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1500);
        assertEq(resolvedOrder.input.amount, 0);
    }

    function testV3ResolveOutputFullyDecayed() public {
        uint256 currentBlock = 1000;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: currentBlock - 200,
                deadline: currentBlock + 200,
                input: V3DutchInput(tokenIn, 100, CurveBuilder.singlePointCurve(200, 100), 100, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 2000, 1000, CurveBuilder.singlePointCurve(200, 1000), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 0);
    }

    function testV3ResolveInputHalfwayDecayed() public {
        uint256 currentBlock = 1000;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: currentBlock - 100,
                deadline: currentBlock + 200,
                input: V3DutchInput(tokenIn, 1000, CurveBuilder.singlePointCurve(200, 1000), 1000, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 1000, 1000, CurveBuilder.singlePointCurve(200, 0), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 500);
    }

    function testV3ResolveInputFullyDecayed() public {
        uint256 currentBlock = 1000;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: currentBlock - 100,
                deadline: currentBlock + 200,
                input: V3DutchInput(tokenIn, 1000, CurveBuilder.singlePointCurve(100, 1000), 1000, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 1000, 1000, CurveBuilder.singlePointCurve(100, 0), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 0);
    }

    // 1000 - (100 * (1659087340-1659029740) / (65535)) = 912.1
    // This is the output, which should round up to favor the swapper: 913
    function testV3ResolveEndBlockAfterNow() public {
        uint256 currentBlock = 1659087340;
        uint16 relativeEndBlock = 65535;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: 1659029740,
                deadline: 1659130540,
                input: V3DutchInput(tokenIn, 0, CurveBuilder.singlePointCurve(relativeEndBlock, 0), 0, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 1000, 900, CurveBuilder.singlePointCurve(relativeEndBlock, 100), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 913);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
    }

    // 1000 - (100 * (1659087340-1659029740) / (65535)) = 912.1
    // This is the input, which should round down to favor the swapper: 912
    function testV3ResolveInputEndBlockAfterNow() public {
        uint256 currentBlock = 1659087340;
        uint16 relativeEndBlock = 65535;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: 1659029740,
                deadline: 1659130540,
                input: V3DutchInput(tokenIn, 1000, CurveBuilder.singlePointCurve(relativeEndBlock, 100), 1000, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 0, 0, CurveBuilder.singlePointCurve(relativeEndBlock, 0), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.input.amount, 912);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.outputs[0].amount, 0);
    }

    // 1000 - (100 * (1659087340-1659029740) / (65535)) = 912.1
    // This is the output, which should round up to favor the swapper: 913
    function testV3ResolveOutputEndBlockAfterNow() public {
        uint256 currentBlock = 1659087340;
        uint16 relativeEndBlock = 65535;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: 1659029740,
                deadline: 1659130540,
                input: V3DutchInput(tokenIn, 0, CurveBuilder.singlePointCurve(relativeEndBlock, 0), 0, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 1000, 900, CurveBuilder.singlePointCurve(relativeEndBlock, 100), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 913);
        assertEq(resolvedOrder.input.amount, 0);
    }

    // 1000 - (-100 * (1659087340-1659029740) / (65535)) = 1087.89...
    // This is the input, which should round down to favor the swapper: 1087
    function testV3ResolvePositiveSlopeInputEndBlockAfterNow() public {
        uint256 currentBlock = 1659087340;
        uint16 relativeEndBlock = 65535;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: 1659029740,
                deadline: 1659130540,
                input: V3DutchInput(tokenIn, 1000, CurveBuilder.singlePointCurve(relativeEndBlock, -100), 1100, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 0, 0, CurveBuilder.singlePointCurve(relativeEndBlock, 0), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.input.amount, 1087);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.outputs[0].amount, 0);
    }

    // 1000 - (-100 * (1659087340-1659029740) / (65535)) = 1087.89...
    // This is the output, which should round up to favor the swapper: 1088
    function testV3ResolvePositiveSlopeOutputEndBlockAfterNow() public {
        uint256 currentBlock = 1659087340;
        uint16 relativeEndBlock = 65535;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: 1659029740,
                deadline: 1659130540,
                input: V3DutchInput(tokenIn, 0, CurveBuilder.singlePointCurve(relativeEndBlock, 0), 0, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 1000, 1000, CurveBuilder.singlePointCurve(relativeEndBlock, -100), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1088);
        assertEq(resolvedOrder.input.amount, 0);
    }

    // Test multiple dutch outputs get resolved correctly.
    function testV3ResolveMultipleDutchOutputs() public {
        uint256 currentBlock = 1659087340;
        uint16 relativeEndBlock = 65535;
        vm.roll(currentBlock);

        NonlinearDutchDecay[] memory curves = new NonlinearDutchDecay[](3);
        curves[0] = CurveBuilder.singlePointCurve(relativeEndBlock, 100);
        curves[1] = CurveBuilder.singlePointCurve(relativeEndBlock, 1000);
        curves[2] = CurveBuilder.singlePointCurve(relativeEndBlock, 1000);
        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: 1659029740,
                deadline: 1659130540,
                input: V3DutchInput(tokenIn, 0, CurveBuilder.singlePointCurve(relativeEndBlock, 0), 0, 0),
                outputs: OutputsBuilder.multipleV3Dutch(
                    address(tokenOut), Solarray.uint256s(1000, 10000, 2000), curves, address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs.length, 3);
        assertEq(resolvedOrder.outputs[0].amount, 913);
        assertEq(resolvedOrder.outputs[1].amount, 9122);
        assertEq(resolvedOrder.outputs[2].amount, 1122);
        assertEq(resolvedOrder.input.amount, 0);
    }

    // Test that when decayStartBlock = now, that the output = startAmount
    function testV3ResolveStartBlockEqualsNow() public {
        uint256 currentBlock = 1659029740;
        uint16 relativeEndBlock = 65535;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: currentBlock,
                deadline: 1659130540,
                input: V3DutchInput(tokenIn, 0, CurveBuilder.singlePointCurve(relativeEndBlock, 0), 0, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 1000, 900, CurveBuilder.singlePointCurve(relativeEndBlock, 100), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
    }

    // At block 99, output will still be 1000. One block later at 100,
    // the first decay will occur and the output will be 999.
    // This is because it is the output, which should round up
    // to favor the swapper (999.01... -> 1000)
    function testV3ResolveFirstDecay() public {
        uint256 startBlock = 0;
        uint256 currentBlock = 99;
        uint16 relativeEndBlock = 10000;
        vm.roll(currentBlock);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: startBlock,
                deadline: 1659130540,
                input: V3DutchInput(tokenIn, 0, CurveBuilder.singlePointCurve(relativeEndBlock, 0), 0, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 1000, 900, CurveBuilder.singlePointCurve(relativeEndBlock, 100), address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);

        vm.roll(currentBlock + 1);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 999);
    }

    function testV3FuzzPositiveDecayNeverOutOfBounds(
        uint128 currentBlock,
        uint128 decayStartBlock,
        uint256 startAmount,
        uint16 decayDuration,
        uint256 decayAmount
    ) public {
        vm.assume(decayAmount < 2 ** 255 - 1);
        vm.assume(startAmount <= UINT256_MAX - decayAmount);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: uint256(currentBlock),
                startBlock: uint256(decayStartBlock),
                deadline: type(uint256).max,
                input: V3DutchInput(tokenIn, 0, CurveBuilder.singlePointCurve(decayDuration, 0), 0, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut),
                    startAmount,
                    startAmount,
                    CurveBuilder.singlePointCurve(decayDuration, 0 - int256(decayAmount)),
                    address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertGe(resolvedOrder.outputs[0].amount, startAmount);
        uint256 endAmount = startAmount + decayAmount;
        assertLe(resolvedOrder.outputs[0].amount, endAmount);
    }

    function testV3FuzzNegativeDecayNeverOutOfBounds(
        uint128 currentBlock,
        uint128 decayStartBlock,
        uint256 startAmount,
        uint16 decayDuration,
        uint256 decayAmount
    ) public {
        vm.assume(decayAmount < 2 ** 255 - 1);
        // can't have neg prices
        vm.assume(startAmount >= decayAmount);
        vm.assume(startAmount <= UINT256_MAX - decayAmount);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: uint256(currentBlock),
                startBlock: uint256(decayStartBlock),
                deadline: type(uint256).max,
                input: V3DutchInput(tokenIn, 0, CurveBuilder.singlePointCurve(decayDuration, 0), 0, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut),
                    startAmount,
                    0,
                    CurveBuilder.singlePointCurve(decayDuration, int256(decayAmount)),
                    address(0)
                )
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertLe(resolvedOrder.outputs[0].amount, startAmount);
        uint256 endAmount = startAmount.sub(int256(decayAmount));
        assertGe(resolvedOrder.outputs[0].amount, endAmount);
    }

    function testV3ResolveMultiPointInputDecay() public {
        uint256 currentBlock = 1000;
        uint256 decayStartBlock = currentBlock + 100;
        vm.roll(currentBlock);

        uint16[] memory blocks = new uint16[](3);
        blocks[0] = 100;
        blocks[1] = 200;
        blocks[2] = 300;
        int256[] memory decayAmounts = new int256[](3);
        decayAmounts[0] = -1 ether; // 2 ether
        decayAmounts[1] = 0 ether; // 1 ether
        decayAmounts[2] = 1 ether; // 0 ether
        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: decayStartBlock,
                deadline: currentBlock + 400,
                input: V3DutchInput(tokenIn, 1 ether, curve, 2 ether, 0),
                outputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 1000, 1000, CurveBuilder.emptyCurve(), address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // decay start block
        vm.roll(decayStartBlock);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // halfway through first decay
        vm.roll(decayStartBlock + 50);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1.5 ether);

        // 20% through second decay
        vm.roll(decayStartBlock + 120);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1.8 ether);

        // 70% through third decay
        vm.roll(decayStartBlock + 270);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 0.3 ether);

        // after last decay (before deadline)
        vm.roll(decayStartBlock + 305);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 0 ether);
    }

    function testV3ResolveMultiPointOutputDecay() public {
        uint256 currentBlock = 1000;
        uint256 decayStartBlock = currentBlock + 100;
        vm.roll(currentBlock);

        uint16[] memory blocks = new uint16[](3);
        blocks[0] = 100;
        blocks[1] = 200;
        blocks[2] = 300;
        int256[] memory decayAmounts = new int256[](3);
        decayAmounts[0] = -1000; // 2000
        decayAmounts[1] = 0; // 1000
        decayAmounts[2] = 1000; // 0
        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: decayStartBlock,
                deadline: currentBlock + 400,
                input: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether, 0),
                outputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 1000, 0, curve, address(0))
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // decay start block
        vm.roll(decayStartBlock);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // halfway through first decay
        vm.roll(decayStartBlock + 50);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1500);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // 20% through second decay
        vm.roll(decayStartBlock + 120);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1800);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // 70% through third decay
        vm.roll(decayStartBlock + 270);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 300);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // after last decay (before deadline)
        vm.roll(decayStartBlock + 305);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 1 ether);
    }

    function testV3ResolveMultiPointMultiOutputDecay() public {
        uint256 currentBlock = 1000;
        uint256 decayStartBlock = currentBlock + 100;
        vm.roll(currentBlock);

        // Two output tokens
        V3DutchOutput[] memory outputs = new V3DutchOutput[](2);
        uint16[] memory blocks = new uint16[](3);
        blocks[0] = 100;
        blocks[1] = 200;
        blocks[2] = 300;
        int256[] memory decayAmounts = new int256[](3);
        decayAmounts[0] = -1000; // 2000
        decayAmounts[1] = 0; // 1000
        decayAmounts[2] = 1000; // 0
        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);
        outputs[0] = OutputsBuilder.singleV3Dutch(address(tokenOut), 1000, 0, curve, address(0))[0];

        // Second token does not decay
        outputs[1] = OutputsBuilder.singleV3Dutch(address(tokenOut2), 1000, 0, CurveBuilder.emptyCurve(), address(0))[0];

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: decayStartBlock,
                deadline: currentBlock + 400,
                input: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether, 0),
                outputs: outputs
            })
        );
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.outputs[1].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // decay start block
        vm.roll(decayStartBlock);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.outputs[1].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // halfway through first decay
        vm.roll(decayStartBlock + 50);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1500);
        assertEq(resolvedOrder.outputs[1].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // 20% through second decay
        vm.roll(decayStartBlock + 120);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1800);
        assertEq(resolvedOrder.outputs[1].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // 70% through third decay
        vm.roll(decayStartBlock + 270);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 300);
        assertEq(resolvedOrder.outputs[1].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // after last decay (before deadline)
        vm.roll(decayStartBlock + 305);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.outputs[1].amount, 1000);
        assertEq(resolvedOrder.input.amount, 1 ether);
    }

    /* Gas adjustment tests */

    function testV3ResolveNoGasAdjustment() public {
        uint256 currentBlock = 1000;
        vm.roll(currentBlock);
        vm.fee(1 gwei);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: currentBlock + 100,
                deadline: currentBlock + 200,
                input: V3DutchInput(tokenIn, 1 ether, CurveBuilder.singlePointCurve(200, 1 ether), 2 ether, 1 gwei),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 0, 0, CurveBuilder.singlePointCurve(200, -100), address(0)
                )
            })
        );

        // Unchanged basefee
        vm.fee(1 gwei);
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 1 ether);
    }

    function testV3ResolveInputGasAdjustment() public {
        uint256 currentBlock = 1000;
        uint256 decayStartBlock = currentBlock + 100;
        vm.roll(currentBlock);
        vm.fee(1 gwei);

        uint16[] memory blocks = new uint16[](3);
        blocks[0] = 100;
        blocks[1] = 200;
        blocks[2] = 300;
        int256[] memory decayAmounts = new int256[](3);
        decayAmounts[0] = -1 ether; // 2 ether
        decayAmounts[1] = 0; // 1 ether
        decayAmounts[2] = 1 ether; // 0 ether
        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: decayStartBlock,
                deadline: currentBlock + 500,
                input: V3DutchInput(tokenIn, 1 ether, curve, 2 ether, 1 gwei),
                outputs: OutputsBuilder.singleV3Dutch(address(tokenOut), 0, 0, CurveBuilder.emptyCurve(), address(0))
            })
        );

        // +1 gwei basefee
        vm.fee(2 gwei);
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 1 ether + 1 gwei);

        // block progression and +2 gwei basefee
        vm.fee(3 gwei);
        vm.roll(decayStartBlock + 50);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 1.5 ether + 2 gwei);

        // block progression but input capped at max amount (2 ether)
        vm.fee(2 gwei);
        vm.roll(decayStartBlock + 100);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 2 ether);

        // block progression and +1 gwei basefee
        vm.fee(2 gwei);
        vm.roll(decayStartBlock + 120);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 1.8 ether + 1 gwei);

        // block progression and -1 gwei basefee
        vm.fee(0 gwei);
        vm.roll(decayStartBlock + 200);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 1 ether - 1 gwei);

        // block progression and -.5 gwei basefee
        vm.fee(0.5 gwei);
        vm.roll(decayStartBlock + 200);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 1 ether - 0.5 gwei);

        // block progression and -0 gwei basefee
        vm.fee(1 gwei);
        vm.roll(decayStartBlock + 250);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 0.5 ether);

        // block progression and -1 gwei basefee
        vm.fee(0 gwei);
        vm.roll(decayStartBlock + 300);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 0 ether); // capped at 0
    }

    function testV3ResolveOutputGasAdjustment() public {
        uint256 currentBlock = 1000;
        uint256 decayStartBlock = currentBlock + 100;
        vm.roll(currentBlock);
        vm.fee(1 gwei);

        uint16[] memory blocks = new uint16[](3);
        blocks[0] = 100;
        blocks[1] = 200;
        blocks[2] = 300;
        int256[] memory decayAmounts = new int256[](3);
        decayAmounts[0] = -1 ether; // 2 ether
        decayAmounts[1] = 0; // 1 ether
        decayAmounts[2] = 0.5 ether; // .5 ether
        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: decayStartBlock,
                deadline: currentBlock + 500,
                input: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 1 ether, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    V3DutchOutput(address(tokenOut), 1 ether, curve, address(0), 0.5 ether, 1 gwei)
                )
            })
        );

        // +1 gwei basefee
        vm.fee(2 gwei);
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1 ether - 1 gwei);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // block progression and +2 gwei basefee
        vm.fee(3 gwei);
        vm.roll(decayStartBlock + 50);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1.5 ether - 2 gwei);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // block progression and +1 gwei basefee
        vm.fee(2 gwei);
        vm.roll(decayStartBlock + 100);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 2 ether - 1 gwei);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // block progression and +1 gwei basefee
        vm.fee(2 gwei);
        vm.roll(decayStartBlock + 120);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1.8 ether - 1 gwei);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // block progression and -1 gwei basefee
        vm.fee(0 gwei);
        vm.roll(decayStartBlock + 200);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1 ether + 1 gwei);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // block progression and -.5 gwei basefee
        vm.fee(0.5 gwei);
        vm.roll(decayStartBlock + 200);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1 ether + 0.5 gwei);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // block progression and -0 gwei basefee
        vm.fee(1 gwei);
        vm.roll(decayStartBlock + 250);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0.75 ether);
        assertEq(resolvedOrder.input.amount, 1 ether);

        // block progression and +4 gwei basefee
        vm.fee(5 gwei);
        vm.roll(decayStartBlock + 300);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0.5 ether); // capped at .5
        assertEq(resolvedOrder.input.amount, 1 ether);
    }

    function testV3ResolveInputGasAdjustmentBounded(uint64 fee, uint128 adjustment, uint256 blockNumber) public {
        uint256 currentBlock = 1000;
        uint256 decayStartBlock = currentBlock + 100;
        vm.roll(currentBlock);
        vm.fee(1 gwei);

        uint16[] memory blocks = new uint16[](3);
        blocks[0] = 100;
        blocks[1] = 200;
        blocks[2] = 300;
        int256[] memory decayAmounts = new int256[](3);
        decayAmounts[0] = -1 ether; // 2 ether
        decayAmounts[1] = 0; // 1 ether
        decayAmounts[2] = 0.5 ether; // .5 ether
        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: decayStartBlock,
                deadline: currentBlock + 500,
                input: V3DutchInput(tokenIn, 1 ether, curve, 2 ether, adjustment),
                outputs: OutputsBuilder.singleV3Dutch(
                    address(tokenOut), 0 ether, 0 ether, CurveBuilder.emptyCurve(), address(0)
                )
            })
        );

        vm.fee(fee);
        vm.roll(blockNumber);
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertLe(resolvedOrder.input.amount, 2 ether);
    }

    function testV3ResolveOutputGasAdjustmentBounded(uint64 fee, uint128 adjustment, uint256 blockNumber) public {
        uint256 currentBlock = 1000;
        uint256 decayStartBlock = currentBlock + 100;
        vm.roll(currentBlock);
        vm.fee(1 gwei);

        uint16[] memory blocks = new uint16[](3);
        blocks[0] = 100;
        blocks[1] = 200;
        blocks[2] = 300;
        int256[] memory decayAmounts = new int256[](3);
        decayAmounts[0] = -1 ether; // 2 ether
        decayAmounts[1] = 0; // 1 ether
        decayAmounts[2] = 0.5 ether; // .5 ether
        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: decayStartBlock,
                deadline: currentBlock + 500,
                input: V3DutchInput(tokenIn, 1 ether, curve, 1 ether, 0),
                outputs: OutputsBuilder.singleV3Dutch(
                    V3DutchOutput(address(tokenOut), 1 ether, CurveBuilder.emptyCurve(), address(0), 0.5 ether, adjustment)
                )
            })
        );

        vm.fee(fee);
        vm.roll(blockNumber);
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertGe(resolvedOrder.outputs[0].amount, 0.5 ether);
    }

    function testV3ResolveSmallGasAdjustments() public {
        uint256 currentBlock = 1000;
        vm.roll(currentBlock);
        vm.fee(1 gwei);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: currentBlock + 100,
                deadline: currentBlock + 200,
                input: V3DutchInput(tokenIn, 1 ether, CurveBuilder.emptyCurve(), 2 ether, 1),
                outputs: OutputsBuilder.singleV3Dutch(
                    V3DutchOutput(address(tokenOut), 1 ether, CurveBuilder.emptyCurve(), address(0), 0.5 ether, 1)
                )
            })
        );

        // +1 gwei basefee = 1 wei change
        vm.fee(2 gwei);
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1 ether - 1);
        assertEq(resolvedOrder.input.amount, 1 ether + 1);

        // -1 gwei basefee = 1 wei change
        vm.fee(0 gwei);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 1 ether + 1);
        assertEq(resolvedOrder.input.amount, 1 ether - 1);
    }

    function testV3ResolveLargeGasAdjustments() public {
        uint256 currentBlock = 1000;
        vm.roll(currentBlock);
        vm.fee(1 gwei);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: currentBlock + 100,
                deadline: currentBlock + 200,
                input: V3DutchInput(
                    tokenIn, type(uint128).max, CurveBuilder.emptyCurve(), type(uint256).max, type(uint128).max
                ),
                outputs: OutputsBuilder.singleV3Dutch(
                    V3DutchOutput(
                        address(tokenOut), type(uint128).max, CurveBuilder.emptyCurve(), address(0), 0, type(uint128).max
                    )
                )
            })
        );

        // +1 gwei basefee = type(uint128).max change
        vm.fee(2 gwei);
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 0);
        assertEq(resolvedOrder.input.amount, 2 * uint256(type(uint128).max));

        // -1 gwei basefee = type(uint128).max change
        vm.fee(0 gwei);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs[0].amount, 2 * uint256(type(uint128).max));
        assertEq(resolvedOrder.input.amount, 0);
    }

    // Test multiple dutch outputs are gas adjusted correctly.
    function testV3ResolveMultipleDutchOutputsWithGasAdjustments() public {
        uint256 currentBlock = 1659087340;
        uint16 relativeEndBlock = 65535;
        vm.roll(currentBlock);
        vm.fee(1 gwei);

        NonlinearDutchDecay[] memory curves = new NonlinearDutchDecay[](3);
        curves[0] = CurveBuilder.singlePointCurve(relativeEndBlock, 100);
        curves[1] = CurveBuilder.singlePointCurve(relativeEndBlock, 1000);
        curves[2] = CurveBuilder.singlePointCurve(relativeEndBlock, 1000);

        V3DutchOutput[] memory outputs = new V3DutchOutput[](3);
        outputs[0] = V3DutchOutput(address(tokenOut), 1000, curves[0], address(0), 0, 1);
        outputs[1] = V3DutchOutput(address(tokenOut), 10000, curves[1], address(0), 0, 1);
        outputs[2] = V3DutchOutput(address(tokenOut), 2000, curves[2], address(0), 0, 1);

        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: 1659029740,
                deadline: 1659130540,
                input: V3DutchInput(tokenIn, 0, CurveBuilder.singlePointCurve(relativeEndBlock, 0), 0, 0),
                outputs: outputs
            })
        );
        vm.fee(2 gwei);
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs.length, 3);
        assertEq(resolvedOrder.outputs[0].amount, 913 - 1);
        assertEq(resolvedOrder.outputs[1].amount, 9122 - 1);
        assertEq(resolvedOrder.outputs[2].amount, 1122 - 1);
        assertEq(resolvedOrder.input.amount, 0);

        vm.fee(0 gwei);
        resolvedOrder = quoter.quote(order.order, order.sig);
        assertEq(resolvedOrder.outputs.length, 3);
        assertEq(resolvedOrder.outputs[0].amount, 913 + 1);
        assertEq(resolvedOrder.outputs[1].amount, 9122 + 1);
        assertEq(resolvedOrder.outputs[2].amount, 1122 + 1);
        assertEq(resolvedOrder.input.amount, 0);
    }

    function testV3GasAdjustmentRounding() public {
        uint256 currentBlock = 21212121;
        vm.roll(currentBlock);
        vm.fee(1 gwei);

        // Order with 1 wei gas adjustments
        SignedOrder memory order = generateOrder(
            TestDutchOrderSpec({
                currentBlock: currentBlock,
                startBlock: currentBlock,
                deadline: currentBlock + 21,
                input: V3DutchInput(tokenIn, 1000, CurveBuilder.emptyCurve(), 1100, 1),
                outputs: OutputsBuilder.singleV3Dutch(
                    V3DutchOutput(address(tokenOut), 1000, CurveBuilder.emptyCurve(), address(0), 900, 1)
                )
            })
        );

        // Test gas increase
        vm.fee(1.5 gwei);
        ResolvedOrder memory resolvedOrder = quoter.quote(order.order, order.sig);
        // The gas adjusted input would be 1000.5, which should round down to 1000
        assertEq(resolvedOrder.input.amount, 1000, "Input should round down");
        // The gas adjusted output would be 999.5, which should round up to 1000
        assertEq(resolvedOrder.outputs[0].amount, 1000, "Output should round up");

        // Test gas decrease
        vm.fee(0.5 gwei);
        resolvedOrder = quoter.quote(order.order, order.sig);
        // The gas adjusted input would be 999.5, which should round down to 999
        assertEq(resolvedOrder.input.amount, 999, "Input should round down");
        // The gas adjusted output would be 1000.5, which should round up to 1001
        assertEq(resolvedOrder.outputs[0].amount, 1001, "Output should round up");

        // Test smaller gas changes
        vm.fee(1.1 gwei);
        resolvedOrder = quoter.quote(order.order, order.sig);
        // The gas adjusted input would be 1000.1, which should round down to 1000
        assertEq(resolvedOrder.input.amount, 1000, "Input should round down");
        // The gas adjusted output would be 999.9, which should round up to 1000
        assertEq(resolvedOrder.outputs[0].amount, 1000, "Output should round up");

        vm.fee(0.9 gwei);
        resolvedOrder = quoter.quote(order.order, order.sig);
        // The gas adjusted input would be 999.9, which should round down to 999
        assertEq(resolvedOrder.input.amount, 999, "Input should round down");
        // The gas adjusted output would be 1000.1, which should round up to 1001
        assertEq(resolvedOrder.outputs[0].amount, 1001, "Output should round up");
    }

    /* Test helpers */

    struct TestDutchOrderSpec {
        uint256 currentBlock;
        uint256 startBlock;
        uint256 deadline;
        V3DutchInput input;
        V3DutchOutput[] outputs;
    }

    /// @dev Create a signed order and return the order and orderHash
    /// @param request Order to sign
    function createAndSignDutchOrder(V3DutchOrder memory request)
        public
        virtual
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        orderHash = request.hash();
        return (SignedOrder(abi.encode(request), signOrder(swapperPrivateKey, address(permit2), request)), orderHash);
    }

    function generateOrder(TestDutchOrderSpec memory spec) internal returns (SignedOrder memory order) {
        tokenIn.mint(address(swapper), uint256(spec.input.maxAmount));
        tokenIn.forceApprove(swapper, address(permit2), spec.input.maxAmount);

        uint256[] memory outputAmounts = new uint256[](spec.outputs.length);
        for (uint256 i = 0; i < spec.outputs.length; i++) {
            outputAmounts[i] = 0;
        }
        CosignerData memory cosignerData = CosignerData({
            decayStartBlock: spec.startBlock,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: outputAmounts
        });
        V3DutchOrder memory request = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withDeadline(spec.deadline).withSwapper(address(swapper)),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: spec.input,
            baseOutputs: spec.outputs,
            cosignerData: cosignerData,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });
        bytes32 orderHash = request.hash();
        request.cosignature = cosignOrder(orderHash, cosignerData);
        (order,) = createAndSignDutchOrder(request);
    }

    function cosignOrder(bytes32 orderHash, CosignerData memory cosignerData) private view returns (bytes memory sig) {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(cosignerData)));
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

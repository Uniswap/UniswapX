// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DutchDecayLib} from "../../src/lib/DutchDecayLib.sol";
import {NonlinearDutchDecayLib} from "../../src/lib/NonlinearDutchDecayLib.sol";
import {V3DutchOutput, V3DutchInput, NonlinearDutchDecay} from "../../src/lib/V3DutchOrderLib.sol";
import {Uint16Array, toUint256} from "../../src/types/Uint16Array.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {CurveBuilder} from "../util/CurveBuilder.sol";
import {BlockNumberish} from "../../src/base/BlockNumberish.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OutputToken, InputToken} from "../../src/base/ReactorStructs.sol";

contract NonlinearDutchDecayLibTest is Test, BlockNumberish {
    MockERC20 tokenIn;
    MockERC20 tokenOut;

    constructor() {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
    }

    function decayInput(
        NonlinearDutchDecay memory curve,
        uint256 startAmount,
        uint256 decayStartBlock,
        uint256 maxAmount
    ) internal view returns (uint256 decayedAmount) {
        V3DutchInput memory input = V3DutchInput(tokenIn, startAmount, curve, maxAmount, 0);
        return NonlinearDutchDecayLib.decay(input, decayStartBlock, _getBlockNumberish()).amount;
    }

    function decayOutput(
        NonlinearDutchDecay memory curve,
        uint256 startAmount,
        uint256 decayStartBlock,
        uint256 minAmount
    ) internal view returns (uint256 decayedAmount) {
        V3DutchOutput memory output = V3DutchOutput(address(tokenOut), startAmount, curve, address(0), minAmount, 0);
        return NonlinearDutchDecayLib.decay(output, decayStartBlock, _getBlockNumberish()).amount;
    }

    function testLocateCurvePositionSingle() public {
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(1, 0);

        vm.startSnapshotGas("V3-LocateCurvePositionSingle");
        (uint16 startPoint, uint16 endPoint, int256 relStartAmount, int256 relEndAmount) =
            NonlinearDutchDecayLib.locateCurvePosition(curve, 1);
        assertEq(startPoint, 0);
        assertEq(endPoint, 1);
        assertEq(relStartAmount, 0);
        assertEq(relEndAmount, 0);

        (startPoint, endPoint, relStartAmount, relEndAmount) = NonlinearDutchDecayLib.locateCurvePosition(curve, 2);
        assertEq(startPoint, 1);
        assertEq(endPoint, 1);
        assertEq(relStartAmount, 0);
        assertEq(relEndAmount, 0);
        vm.stopSnapshotGas();
    }

    function testLocateCurvePositionMulti() public {
        uint16[] memory blocks = new uint16[](3);
        blocks[0] = 100;
        blocks[1] = 200;
        blocks[2] = 300;
        int256[] memory decayAmounts = new int256[](3);
        decayAmounts[0] = -1 ether; // 2 ether
        decayAmounts[1] = 0 ether; // 1 ether
        decayAmounts[2] = 1 ether; // 0 ether
        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);

        vm.startSnapshotGas("V3-LocateCurvePositionMulti");
        // currentRelativeBlock shouldn't be less than the first block
        // but testing behavior anyways
        (uint16 startPoint, uint16 endPoint, int256 relStartAmount, int256 relEndAmount) =
            NonlinearDutchDecayLib.locateCurvePosition(curve, 50);
        assertEq(startPoint, 0);
        assertEq(endPoint, 100);
        assertEq(relStartAmount, 0);
        assertEq(relEndAmount, -1 ether);

        (startPoint, endPoint, relStartAmount, relEndAmount) = NonlinearDutchDecayLib.locateCurvePosition(curve, 100);
        assertEq(startPoint, 0);
        assertEq(endPoint, 100);
        assertEq(relStartAmount, 0);
        assertEq(relEndAmount, -1 ether);

        (startPoint, endPoint, relStartAmount, relEndAmount) = NonlinearDutchDecayLib.locateCurvePosition(curve, 150);
        assertEq(startPoint, 100);
        assertEq(endPoint, 200);
        assertEq(relStartAmount, -1 ether);
        assertEq(relEndAmount, 0 ether);

        (startPoint, endPoint, relStartAmount, relEndAmount) = NonlinearDutchDecayLib.locateCurvePosition(curve, 200);
        assertEq(startPoint, 100);
        assertEq(endPoint, 200);
        assertEq(relStartAmount, -1 ether);
        assertEq(relEndAmount, 0 ether);

        (startPoint, endPoint, relStartAmount, relEndAmount) = NonlinearDutchDecayLib.locateCurvePosition(curve, 250);
        assertEq(startPoint, 200);
        assertEq(endPoint, 300);
        assertEq(relStartAmount, 0 ether);
        assertEq(relEndAmount, 1 ether);

        (startPoint, endPoint, relStartAmount, relEndAmount) = NonlinearDutchDecayLib.locateCurvePosition(curve, 300);
        assertEq(startPoint, 200);
        assertEq(endPoint, 300);
        assertEq(relStartAmount, 0 ether);
        assertEq(relEndAmount, 1 ether);

        (startPoint, endPoint, relStartAmount, relEndAmount) = NonlinearDutchDecayLib.locateCurvePosition(curve, 350);
        assertEq(startPoint, 300);
        assertEq(endPoint, 300);
        assertEq(relStartAmount, 1 ether);
        assertEq(relEndAmount, 1 ether);
        vm.stopSnapshotGas();
    }

    function testDutchDecayNoDecay(uint256 startAmount, uint256 decayStartBlock) public {
        // Empty curve
        vm.startSnapshotGas("V3-DutchDecayNoDecay");
        assertEq(decayOutput(CurveBuilder.emptyCurve(), startAmount, decayStartBlock, startAmount), startAmount);

        // Single value with 0 amount change
        assertEq(
            decayOutput(CurveBuilder.singlePointCurve(1, 0), startAmount, decayStartBlock, startAmount), startAmount
        );
        vm.stopSnapshotGas();
    }

    function testDutchDecayNoDecayYet() public {
        uint256 decayStartBlock = 200;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -1 ether;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(1, decayAmount);
        vm.startSnapshotGas("V3-DutchDecayNoDecayYet");
        vm.roll(100);
        // at decayStartBlock
        assertEq(decayOutput(curve, startAmount, decayStartBlock, startAmount), startAmount);

        vm.roll(80);
        // before decayStartBlock
        assertEq(decayOutput(curve, startAmount, decayStartBlock, startAmount), startAmount);
        vm.stopSnapshotGas();
    }

    function testDutchDecayNoDecayYetNegative() public {
        uint256 decayStartBlock = 200;
        uint256 startAmount = 1 ether;
        int256 decayAmount = 1 ether;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(1, decayAmount);
        vm.startSnapshotGas("V3-DutchDecayNoDecayYetNegative");
        vm.roll(100);
        // at decayStartBlock
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0), startAmount);

        vm.roll(80);
        // before decayStartBlock
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0), startAmount);
        vm.stopSnapshotGas();
    }

    function testDutchDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -1 ether;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(100, decayAmount);
        vm.startSnapshotGas("V3-DutchDecay");
        vm.roll(150);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.5 ether);

        vm.roll(180);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.8 ether);

        vm.roll(110);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.1 ether);

        vm.roll(190);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.9 ether);
        vm.stopSnapshotGas();
    }

    function testDutchInputDecayRounding() public {
        uint256 decayStartBlock = 0;
        uint256 startAmount = 2000;
        int256 decayAmount = 1000;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(10000, decayAmount);

        vm.roll(0);
        assertEq(decayInput(curve, startAmount, decayStartBlock, 3000), 2000);

        vm.roll(1);
        // Input should round down to favor the swapper
        assertEq(decayInput(curve, startAmount, decayStartBlock, 3000), 1999);

        vm.roll(9);
        assertEq(decayInput(curve, startAmount, decayStartBlock, 3000), 1999);
    }

    function testDutchOutputDecayRounding() public {
        uint256 decayStartBlock = 0;
        uint256 startAmount = 2000;
        int256 decayAmount = 1000;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(10000, decayAmount);

        vm.roll(0);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1000), 2000);

        vm.roll(1);
        // Output should round up to favor the swapper
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1000), 2000);

        vm.roll(9);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1000), 2000);

        vm.roll(10);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1000), 1999);
    }

    function testDutchInputUpwardDecayRounding() public {
        uint256 decayStartBlock = 0;
        uint256 startAmount = 2000;
        int256 decayAmount = -1000;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(10000, decayAmount);

        vm.roll(0);
        assertEq(decayInput(curve, startAmount, decayStartBlock, 3000), 2000);

        vm.roll(1);
        // Input should round down to favor the swapper
        assertEq(decayInput(curve, startAmount, decayStartBlock, 3000), 2000);

        vm.roll(9);
        assertEq(decayInput(curve, startAmount, decayStartBlock, 3000), 2000);

        vm.roll(10);
        assertEq(decayInput(curve, startAmount, decayStartBlock, 3000), 2001);
    }

    function testDutchOutputUpwardDecayRounding() public {
        uint256 decayStartBlock = 0;
        uint256 startAmount = 2000;
        int256 decayAmount = -1000;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(10000, decayAmount);

        vm.roll(0);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1000), 2000);

        vm.roll(1);
        // Output should round up to favor the swapper
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1000), 2001);

        vm.roll(9);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1000), 2001);

        vm.roll(10);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1000), 2001);

        vm.roll(11);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1000), 2002);
    }

    function testDutchDecayNegative() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 2 ether;
        int256 decayAmount = 1 ether;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(100, decayAmount);
        vm.startSnapshotGas("V3-DutchDecayNegative");
        vm.roll(150);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.5 ether);

        vm.roll(180);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.2 ether);

        vm.roll(110);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.9 ether);

        vm.roll(190);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.1 ether);
        vm.stopSnapshotGas();
    }

    function testDutchDecayFullyDecayed() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -1 ether;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(100, decayAmount);
        vm.startSnapshotGas("V3-DutchDecayFullyDecayed");
        vm.roll(200);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 2 ether);

        vm.warp(250);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 2 ether);
        vm.stopSnapshotGas();
    }

    function testDutchDecayFullyDecayedNegative() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 2 ether;
        int256 decayAmount = 1 ether;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(100, decayAmount);
        vm.startSnapshotGas("V3-DutchDecayFullyDecayedNegative");
        vm.roll(200);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1 ether);

        vm.warp(250);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1 ether);
        vm.stopSnapshotGas();
    }

    function testDutchDecayRange(uint256 startAmount, int256 decayAmount, uint256 decayStartBlock, uint16 decayDuration)
        public
    {
        vm.assume(decayAmount > 0);
        vm.assume(startAmount <= uint256(type(int256).max - decayAmount));

        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(decayDuration, 0 - int256(decayAmount));
        vm.startSnapshotGas("V3-DutchDecayRange");
        uint256 decayed = decayOutput(curve, startAmount, decayStartBlock, 0);
        assertGe(decayed, startAmount);
        assertLe(decayed, startAmount + uint256(decayAmount));
        vm.stopSnapshotGas();
    }

    function testDutchDecayBounded(
        uint256 startAmount,
        int256 decayAmount,
        uint256 decayStartBlock,
        uint16 decayDuration,
        uint256 minAmount
    ) public {
        vm.assume(decayAmount > 0);
        vm.assume(startAmount <= uint256(type(int256).max - decayAmount));

        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(decayDuration, 0 - int256(decayAmount));
        vm.startSnapshotGas("V3-DutchDecayBounded");
        uint256 decayed = decayOutput(curve, startAmount, decayStartBlock, minAmount);
        assertGe(decayed, minAmount);
        vm.stopSnapshotGas();
    }

    function testDutchDecayNegative(
        uint256 startAmount,
        uint256 decayAmount,
        uint256 decayStartBlock,
        uint16 decayDuration
    ) public {
        vm.assume(decayAmount > 0);
        vm.assume(decayAmount < 2 ** 255 - 1);
        // can't have neg prices
        vm.assume(startAmount >= decayAmount);
        vm.assume(startAmount <= UINT256_MAX - decayAmount);

        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(decayDuration, int256(decayAmount));
        vm.startSnapshotGas("V3-DutchDecayNegative");
        uint256 decayed = decayOutput(curve, startAmount, decayStartBlock, 0);
        assertLe(decayed, startAmount);
        assertGe(decayed, startAmount - decayAmount);
        vm.stopSnapshotGas();
    }

    function testMultiPointDutchDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        uint16[] memory blocks = new uint16[](3);
        blocks[0] = 100; // block 200
        blocks[1] = 200; // block 300
        blocks[2] = 300; // block 400
        int256[] memory decayAmounts = new int256[](3);
        decayAmounts[0] = -1 ether; // 2 ether
        decayAmounts[1] = 0 ether; // 1 ether
        decayAmounts[2] = 1 ether; // 0 ether
        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);
        vm.startSnapshotGas("V3-MultiPointDutchDecay");
        vm.roll(50);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 1 ether);

        vm.roll(150);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 1.5 ether);

        vm.roll(200);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 2 ether);

        vm.roll(210);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 1.9 ether);

        vm.roll(290);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 1.1 ether);

        vm.roll(300);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 1 ether);

        vm.roll(350);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 0.5 ether);

        vm.roll(400);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 0 ether);

        vm.roll(500);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 0 ether);
        vm.stopSnapshotGas();
    }

    function testExtendedMultiPointDutchDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        uint16[] memory blocks = new uint16[](16);
        blocks[0] = 100; // block 200
        blocks[1] = 200; // block 300
        blocks[2] = 300; // block 400
        blocks[3] = 400; // block 500
        blocks[4] = 500; // block 600
        blocks[5] = 600; // block 700
        blocks[6] = 700; // block 800
        blocks[7] = 800; // block 900
        blocks[8] = 900; // block 1000
        blocks[9] = 1000; // block 1100
        blocks[10] = 1100; // block 1200
        blocks[11] = 1200; // block 1300
        blocks[12] = 1300; // block 1400
        blocks[13] = 1400; // block 1500
        blocks[14] = 1500; // block 1600
        blocks[15] = 1600; // block 1700

        int256[] memory decayAmounts = new int256[](16);
        decayAmounts[0] = -0.1 ether;
        decayAmounts[1] = -0.2 ether;
        decayAmounts[2] = -0.3 ether;
        decayAmounts[3] = -0.4 ether;
        decayAmounts[4] = -0.5 ether;
        decayAmounts[5] = -0.6 ether;
        decayAmounts[6] = -0.7 ether;
        decayAmounts[7] = -0.8 ether;
        decayAmounts[8] = -0.9 ether;
        decayAmounts[9] = -1 ether;
        decayAmounts[10] = -0.9 ether;
        decayAmounts[11] = -0.8 ether;
        decayAmounts[12] = -0.7 ether;
        decayAmounts[13] = -0.6 ether;
        decayAmounts[14] = -0.5 ether;
        decayAmounts[15] = -0.4 ether;

        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);
        vm.startSnapshotGas("V3-ExtendedMultiPointDutchDecay");

        vm.roll(50);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1 ether);

        vm.roll(150);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.05 ether); // halfway between 100 (1 ether) and 200 (1.1 ether)

        vm.roll(200);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.1 ether); // 1 + 0.1 ether

        vm.roll(250);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.15 ether); // halfway between 200 (1.1 ether) and 300 (1.2 ether)

        vm.roll(300);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.2 ether); // 1 + 0.2 ether

        vm.roll(350);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.25 ether); // halfway between 300 (1.2 ether) and 400 (1.3 ether)

        vm.roll(400);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.3 ether); // 1 + 0.3 ether

        vm.roll(450);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.35 ether); // halfway between 400 (1.3 ether) and 500 (1.4 ether)

        vm.roll(500);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.4 ether); // 1 + 0.4 ether

        vm.roll(600);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.5 ether); // 1 + 0.5 ether

        vm.roll(700);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.6 ether); // 1 + 0.6 ether

        vm.roll(800);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.7 ether); // 1 + 0.7 ether

        vm.roll(900);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.8 ether); // 1 + 0.8 ether

        vm.roll(1000);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.9 ether); // 1 + 0.9 ether

        vm.roll(1100);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 2 ether); // 1 + 1 ether

        vm.roll(1200);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.9 ether); // 1 + 0.9 ether

        vm.roll(1300);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.8 ether); // 1 + 0.8 ether

        vm.roll(1400);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.7 ether); // 1 + 0.7 ether

        vm.roll(1500);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.6 ether); // 1 + 0.6 ether

        vm.roll(1600);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.5 ether); // 1 + 0.5 ether

        vm.roll(1650);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 1 ether), 1.45 ether); // 1 + 0.45 ether

        vm.stopSnapshotGas();
    }

    /* Invalid order scenarios */

    function testDutchDecayNonAscendingBlocks() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        uint16[] memory blocks = new uint16[](3);
        blocks[0] = 200; // block 300
        blocks[1] = 100; // block 200
        blocks[2] = 300; // block 400
        int256[] memory decayAmounts = new int256[](3);
        decayAmounts[0] = -1 ether; // 2 ether
        decayAmounts[1] = 0 ether; // 1 ether
        decayAmounts[2] = 1 ether; // 0 ether
        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);
        vm.roll(350);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 0.25 ether);
    }

    function testDutchDecayToNegative() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = 2 ether;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(100, decayAmount);
        vm.roll(150);
        assertEq(decayOutput(curve, startAmount, decayStartBlock, 0 ether), 0);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testDutchOverflowDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = type(int256).min;
        NonlinearDutchDecay memory curve = CurveBuilder.singlePointCurve(100, decayAmount);
        vm.roll(150);
        vm.expectRevert();
        decayOutput(curve, startAmount, decayStartBlock, 1 ether);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testDutchMismatchedDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        NonlinearDutchDecay memory curve =
            CurveBuilder.multiPointCurve(ArrayBuilder.fillUint16(16, 1), ArrayBuilder.fillInt(17, 0));
        vm.expectRevert(NonlinearDutchDecayLib.InvalidDecayCurve.selector);
        decayOutput(curve, startAmount, decayStartBlock, 1 ether);
    }

    function testFuzzDutchDecayInputBeyondUint16Max(
        uint16 lastValidBlock, // For curve
        uint256 decayAmountFuzz, // For curve
        // decayInput(curve, startAmount, decayStartBlock, maxAmount);
        uint256 startAmount,
        uint256 decayStartBlock,
        uint256 maxAmount,
        uint256 currentBlock
    ) public {
        vm.assume(decayStartBlock < type(uint256).max - type(uint16).max);
        vm.assume(lastValidBlock > 0);
        vm.assume(startAmount > 0 && startAmount < uint256(type(int256).max));
        vm.assume(maxAmount >= startAmount);
        // bound only takes uint256, so we need to limit decayAmountFuzz to int256.max
        // because we cast it to int256 in the decay function
        decayAmountFuzz = bound(decayAmountFuzz, 0, startAmount);

        // Testing that we get a fully decayed curve instead of overflowed mistake
        // This will happen when the block delta is larger than type(uint16).max
        vm.assume(currentBlock > decayStartBlock + type(uint16).max);

        uint16[] memory blocks = new uint16[](1);
        blocks[0] = lastValidBlock;

        int256[] memory decayAmounts = new int256[](1);
        decayAmounts[0] = int256(decayAmountFuzz);

        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);

        vm.roll(currentBlock);
        uint256 decayed = decayInput(curve, startAmount, decayStartBlock, maxAmount);
        assertEq(
            decayed,
            Math.min(startAmount - decayAmountFuzz, maxAmount),
            "Should be fully decayed for block delta beyond uint16.max"
        );
    }

    function testFuzzDutchDecayOutputBeyondUint16Max(
        uint16 lastValidBlock, // For curve
        uint256 decayAmountFuzz, // For curve
        // decayOutput(curve, startAmount, decayStartBlock, minAmount);
        uint256 startAmount,
        uint256 decayStartBlock,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 currentBlock
    ) public {
        vm.assume(decayStartBlock < type(uint256).max - type(uint16).max);
        vm.assume(lastValidBlock > 0);
        vm.assume(startAmount > 0 && startAmount < uint256(type(int256).max));
        vm.assume(maxAmount >= startAmount);
        minAmount = bound(minAmount, 0, startAmount);
        // bound only takes uint256, so we need to limit decayAmountFuzz to int256.max
        // because we cast it to int256 in the decay function
        decayAmountFuzz = bound(decayAmountFuzz, minAmount, startAmount);

        // Testing that we get a fully decayed curve instead of overflowed mistake
        // This will happen when the block delta is larger than type(uint16).max
        vm.assume(currentBlock > decayStartBlock + type(uint16).max);

        uint16[] memory blocks = new uint16[](1);
        blocks[0] = lastValidBlock;

        int256[] memory decayAmounts = new int256[](1);
        decayAmounts[0] = int256(decayAmountFuzz);

        NonlinearDutchDecay memory curve = CurveBuilder.multiPointCurve(blocks, decayAmounts);

        vm.roll(currentBlock);
        uint256 decayed = decayOutput(curve, startAmount, decayStartBlock, minAmount);
        assertEq(
            decayed,
            Math.max(startAmount - decayAmountFuzz, minAmount),
            "Should be fully decayed for block delta beyond uint16.max"
        );
    }
}

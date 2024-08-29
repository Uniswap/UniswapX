// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {console} from "forge-std/console.sol";
import {NonLinearDutchDecayLib, InvalidDecayCurve} from "../../src/lib/NonLinearDutchDecayLib.sol";
import {NonLinearDutchOutput, NonLinearDutchInput, NonLinearDecay} from "../../src/lib/NonLinearDutchOrderLib.sol";
import {Uint16Array, toUint256} from "../../src/types/Uint16Array.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {NegativeUint} from "../../src/lib/MathExt.sol";

/// @notice mock contract to test NonLinearDutchDecayLib functionality
contract MockNonLinearDutchDecayLibContract {
    function decay(NonLinearDecay memory curve, uint256 startAmount, uint256 decayStartBlock) public view {
        NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock);
    }
}

contract NonLinearDutchDecayLibTest is Test, GasSnapshot {
    MockNonLinearDutchDecayLibContract mockNonLinearDutchDecayLibContract = new MockNonLinearDutchDecayLibContract();

    function testLocateCurvePositionSingle() public {
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, 1)),
            relativeAmounts: ArrayBuilder.fillInt(1, 0)
        });
        snapStart("NonLinear-LocateCurvePositionSingle");
        uint16 prev;
        uint16 next;
        (prev, next) = NonLinearDutchDecayLib.locateCurvePosition(curve, 1);
        assertEq(prev, 0);
        assertEq(next, 0);

        (prev, next) = NonLinearDutchDecayLib.locateCurvePosition(curve, 2);
        assertEq(prev, 0);
        assertEq(next, 0);
        snapEnd();
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
        NonLinearDecay memory curve =
            NonLinearDecay({relativeBlocks: toUint256(blocks), relativeAmounts: decayAmounts});

        snapStart("NonLinear-LocateCurvePositionMulti");
        uint16 prev;
        uint16 next;
        // currentRelativeBlock shouldn't be less than the first block
        // but testing behavior anyways
        (prev, next) = NonLinearDutchDecayLib.locateCurvePosition(curve, 50);
        assertEq(prev, 0);
        assertEq(next, 0);

        (prev, next) = NonLinearDutchDecayLib.locateCurvePosition(curve, 100);
        assertEq(prev, 0);
        assertEq(next, 0);

        (prev, next) = NonLinearDutchDecayLib.locateCurvePosition(curve, 150);
        assertEq(prev, 0);
        assertEq(next, 1);

        (prev, next) = NonLinearDutchDecayLib.locateCurvePosition(curve, 200);
        assertEq(prev, 0);
        assertEq(next, 1);

        (prev, next) = NonLinearDutchDecayLib.locateCurvePosition(curve, 250);
        assertEq(prev, 1);
        assertEq(next, 2);

        (prev, next) = NonLinearDutchDecayLib.locateCurvePosition(curve, 300);
        assertEq(prev, 1);
        assertEq(next, 2);

        (prev, next) = NonLinearDutchDecayLib.locateCurvePosition(curve, 350);
        assertEq(prev, 2);
        assertEq(next, 2);
        snapEnd();
    }

    function testDutchDecayNoDecay(uint256 startAmount, uint256 decayStartBlock) public {
        // Empty curve
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(0, 0)),
            relativeAmounts: ArrayBuilder.fillInt(0, 0)
        });
        snapStart("NonLinear-DutchDecayNoDecay");
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);

        // Single value with 0 amount change
        curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, 1)),
            relativeAmounts: ArrayBuilder.fillInt(1, 0)
        });
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);
        snapEnd();
    }

    function testDutchDecayNoDecayYet() public {
        uint256 decayStartBlock = 200;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, 1)),
            relativeAmounts: ArrayBuilder.fillInt(1, decayAmount)
        });
        snapStart("NonLinear-DutchDecayNoDecayYet");
        vm.roll(100);
        // at decayStartBlock
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);

        vm.roll(80);
        // before decayStartBlock
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);
        snapEnd();
    }

    function testDutchDecayNoDecayYetNegative() public {
        uint256 decayStartBlock = 200;
        uint256 startAmount = 1 ether;
        int256 decayAmount = 1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, 1)),
            relativeAmounts: ArrayBuilder.fillInt(1, decayAmount)
        });
        snapStart("NonLinear-DutchDecayNoDecayYetNegative");
        vm.roll(100);
        // at decayStartBlock
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);

        vm.roll(80);
        // before decayStartBlock
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);
        snapEnd();
    }

    function testDutchDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, 100)),
            relativeAmounts: ArrayBuilder.fillInt(1, decayAmount)
        });
        snapStart("NonLinear-DutchDecay");
        vm.roll(150);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.5 ether);

        vm.roll(180);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.8 ether);

        vm.roll(110);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.1 ether);

        vm.roll(190);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.9 ether);
        snapEnd();
    }

    function testDutchDecayNegative() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 2 ether;
        int256 decayAmount = 1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, 100)),
            relativeAmounts: ArrayBuilder.fillInt(1, decayAmount)
        });
        snapStart("NonLinear-DutchDecayNegative");
        vm.roll(150);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.5 ether);

        vm.roll(180);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.2 ether);

        vm.roll(110);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.9 ether);

        vm.roll(190);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.1 ether);
        snapEnd();
    }

    function testDutchDecayFullyDecayed() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, 100)),
            relativeAmounts: ArrayBuilder.fillInt(1, decayAmount)
        });
        snapStart("NonLinear-DutchDecayFullyDecayed");
        vm.roll(200);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 2 ether);

        vm.warp(250);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 2 ether);
        snapEnd();
    }

    function testDutchDecayFullyDecayedNegative() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 2 ether;
        int256 decayAmount = 1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, 100)),
            relativeAmounts: ArrayBuilder.fillInt(1, decayAmount)
        });
        snapStart("NonLinear-DutchDecayFullyDecayedNegative");
        vm.roll(200);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1 ether);

        vm.warp(250);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1 ether);
        snapEnd();
    }

    function testDutchDecayBounded(
        uint256 startAmount,
        uint256 decayAmount,
        uint256 decayStartBlock,
        uint16 decayDuration
    ) public {
        vm.assume(decayAmount > 0);
        vm.assume(decayAmount < 2 ** 255 - 1);
        vm.assume(startAmount <= UINT256_MAX - decayAmount);
        vm.assume(decayDuration > 0);

        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, decayDuration)),
            relativeAmounts: ArrayBuilder.fillInt(1, 0 - int256(decayAmount))
        });
        snapStart("NonLinear-DutchDecayBounded");
        uint256 decayed = NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock);
        assertGe(decayed, startAmount);
        assertLe(decayed, startAmount + decayAmount);
        snapEnd();
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
        vm.assume(decayDuration > 0);

        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, decayDuration)),
            relativeAmounts: ArrayBuilder.fillInt(1, int256(decayAmount))
        });
        snapStart("NonLinear-DutchDecayNegative");
        uint256 decayed = NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock);
        assertLe(decayed, startAmount);
        assertGe(decayed, startAmount - decayAmount);
        snapEnd();
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
        NonLinearDecay memory curve =
            NonLinearDecay({relativeBlocks: toUint256(blocks), relativeAmounts: decayAmounts});
        snapStart("NonLinear-MultiPointDutchDecay");
        vm.roll(50);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1 ether);

        vm.roll(150);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.5 ether);

        vm.roll(200);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 2 ether);

        vm.roll(210);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.9 ether);

        vm.roll(290);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.1 ether);

        vm.roll(300);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1 ether);

        vm.roll(350);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 0.5 ether);

        vm.roll(400);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 0 ether);

        vm.roll(500);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 0 ether);
        snapEnd();
    }
    
    function testExtendedMultiPointDutchDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        uint16[] memory blocks = new uint16[](16);
        blocks[0] = 100;  // block 200
        blocks[1] = 200;  // block 300
        blocks[2] = 300;  // block 400
        blocks[3] = 400;  // block 500
        blocks[4] = 500;  // block 600
        blocks[5] = 600;  // block 700
        blocks[6] = 700;  // block 800
        blocks[7] = 800;  // block 900
        blocks[8] = 900;  // block 1000
        blocks[9] = 1000; // block 1100
        blocks[10] = 1100;// block 1200
        blocks[11] = 1200;// block 1300
        blocks[12] = 1300;// block 1400
        blocks[13] = 1400;// block 1500
        blocks[14] = 1500;// block 1600
        blocks[15] = 1600;// block 1700

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

        NonLinearDecay memory curve =
            NonLinearDecay({relativeBlocks: toUint256(blocks), relativeAmounts: decayAmounts});
        snapStart("NonLinear-ExtendedMultiPointDutchDecay");

        vm.roll(50);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1 ether);

        vm.roll(150);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.05 ether); // halfway between 100 (1 ether) and 200 (1.1 ether)

        vm.roll(200);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.1 ether); // 1 + 0.1 ether

        vm.roll(250);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.15 ether); // halfway between 200 (1.1 ether) and 300 (1.2 ether)

        vm.roll(300);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.2 ether); // 1 + 0.2 ether

        vm.roll(350);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.25 ether); // halfway between 300 (1.2 ether) and 400 (1.3 ether)

        vm.roll(400);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.3 ether); // 1 + 0.3 ether

        vm.roll(450);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.35 ether); // halfway between 400 (1.3 ether) and 500 (1.4 ether)

        vm.roll(500);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.4 ether); // 1 + 0.4 ether

        vm.roll(600);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.5 ether); // 1 + 0.5 ether

        vm.roll(700);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.6 ether); // 1 + 0.6 ether

        vm.roll(800);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.7 ether); // 1 + 0.7 ether

        vm.roll(900);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.8 ether); // 1 + 0.8 ether

        vm.roll(1000);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.9 ether); // 1 + 0.9 ether

        vm.roll(1100);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 2 ether); // 1 + 1 ether

        vm.roll(1200);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.9 ether); // 1 + 0.9 ether

        vm.roll(1300);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.8 ether); // 1 + 0.8 ether

        vm.roll(1400);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.7 ether); // 1 + 0.7 ether

        vm.roll(1500);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.6 ether); // 1 + 0.6 ether

        vm.roll(1600);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.5 ether); // 1 + 0.5 ether

        vm.roll(1650);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.45 ether); // 1 + 0.45 ether

        snapEnd();
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
        NonLinearDecay memory curve =
            NonLinearDecay({relativeBlocks: toUint256(blocks), relativeAmounts: decayAmounts});
        vm.roll(350);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 0.25 ether);
    }

    function testDutchDecayToNegative() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = 2 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, 100)),
            relativeAmounts: ArrayBuilder.fillInt(1, decayAmount)
        });
        vm.roll(150);
        vm.expectRevert(NegativeUint.selector);
        mockNonLinearDutchDecayLibContract.decay(curve, startAmount, decayStartBlock);
    }

    function testDutchOverflowDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -(2 ** 255 - 1);
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, 100)),
            relativeAmounts: ArrayBuilder.fillInt(1, decayAmount)
        });
        vm.roll(150);
        vm.expectRevert();
        mockNonLinearDutchDecayLibContract.decay(curve, startAmount, decayStartBlock);
    }

    function testDutchMismatchedDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(16, 1)),
            relativeAmounts: ArrayBuilder.fillInt(17, 0)
        });
        vm.roll(150);
        vm.expectRevert(InvalidDecayCurve.selector);
        mockNonLinearDutchDecayLibContract.decay(curve, startAmount, decayStartBlock);
    }
}

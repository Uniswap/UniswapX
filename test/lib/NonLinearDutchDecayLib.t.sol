// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {NonLinearDutchDecayLib} from "../../src/lib/NonLinearDutchDecayLib.sol";
import {NonLinearDutchOutput, NonLinearDutchInput, NonLinearDecay} from "../../src/lib/NonLinearDutchOrderLib.sol";
import {Util} from "../../src/lib/Util.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";

/// @notice mock contract to test NonLinearDutchDecayLib functionality
contract MockNonLinearDutchDecayLibContract {
    function decay(NonLinearDecay memory curve, uint256 startAmount, uint256 decayStartBlock) public view {
        NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock);
    }
}
contract NonLinearDutchDecayLibTest is Test {
    MockNonLinearDutchDecayLibContract mockNonLinearDutchDecayLibContract = new MockNonLinearDutchDecayLibContract();

    function testDutchDecayNoDecay(uint256 startAmount, uint256 decayStartBlock) public {
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, 1)),
            relativeAmount: ArrayBuilder.fillInt(1, 0)
        });
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);
    }

    function testDutchDecayNoDecayYet() public {
        uint256 decayStartBlock = 200;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, 1)),
            relativeAmount: ArrayBuilder.fillInt(1, decayAmount)
        });
        vm.roll(100);
        // at decayStartBlock
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);

        vm.roll(80);
        // before decayStartBlock
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);
    }

    function testDutchDecayNoDecayYetNegative() public {
        uint256 decayStartBlock = 200;
        uint256 startAmount = 1 ether;
        int256 decayAmount = 1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, 1)),
            relativeAmount: ArrayBuilder.fillInt(1, decayAmount)
        });
        vm.roll(100);
        // at decayStartBlock
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);

        vm.roll(80);
        // before decayStartBlock
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), startAmount);
    }

    function testDutchDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, 100)),
            relativeAmount: ArrayBuilder.fillInt(1, decayAmount)
        });
        vm.roll(150);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.5 ether);

        vm.roll(180);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.8 ether);

        vm.roll(110);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.1 ether);

        vm.roll(190);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.9 ether);
    }

    function testDutchDecayNegative() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 2 ether;
        int256 decayAmount = 1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, 100)),
            relativeAmount: ArrayBuilder.fillInt(1, decayAmount)
        });
        vm.roll(150);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.5 ether);

        vm.roll(180);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.2 ether);

        vm.roll(110);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.9 ether);

        vm.roll(190);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1.1 ether);
    }

    function testDutchDecayFullyDecayed() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, 100)),
            relativeAmount: ArrayBuilder.fillInt(1, decayAmount)
        });
        vm.roll(200);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 2 ether);

        vm.warp(250);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 2 ether);
    }

    function testDutchDecayFullyDecayedNegative() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 2 ether;
        int256 decayAmount = 1 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, 100)),
            relativeAmount: ArrayBuilder.fillInt(1, decayAmount)
        });
        vm.roll(200);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1 ether);

        vm.warp(250);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 1 ether);
    }

    function testDutchDecayBounded(uint256 startAmount, uint256 decayAmount, uint256 decayStartBlock, uint16 decayDuration)
        public
    {
        vm.assume(decayAmount > 0);
        vm.assume(decayAmount < 2**255-1);
        vm.assume(startAmount <= UINT256_MAX - decayAmount);
        vm.assume(decayDuration > 0);

        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, decayDuration)),
            relativeAmount: ArrayBuilder.fillInt(1, 0-int256(decayAmount))
        });
        uint256 decayed = NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock);
        assertGe(decayed, startAmount);
        assertLe(decayed, startAmount + decayAmount);
    }

    function testDutchDecayNegative(uint256 startAmount, uint256 decayAmount, uint256 decayStartBlock, uint16 decayDuration)
        public
    {
        vm.assume(decayAmount > 0);
        vm.assume(decayAmount < 2**255-1);
        // can't have neg prices
        vm.assume(startAmount >= decayAmount);
        vm.assume(startAmount <= UINT256_MAX - decayAmount);
        vm.assume(decayDuration > 0);

        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, decayDuration)),
            relativeAmount: ArrayBuilder.fillInt(1, int256(decayAmount))
        });
        uint256 decayed = NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock);
        assertLe(decayed, startAmount);
        assertGe(decayed, startAmount - decayAmount);
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
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(blocks),
            relativeAmount: decayAmounts
        });
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
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), .5 ether);

        vm.roll(400);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 0 ether);

        vm.roll(500);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), 0 ether);
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
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(blocks),
            relativeAmount: decayAmounts
        });
        vm.roll(350);
        assertEq(NonLinearDutchDecayLib.decay(curve, startAmount, decayStartBlock), .25 ether);
    }

    function testDutchDecayToNegative() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = 2 ether;
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, 100)),
            relativeAmount: ArrayBuilder.fillInt(1, decayAmount)
        });
        vm.roll(150);
        vm.expectRevert(Util.NegativeUint.selector);
        mockNonLinearDutchDecayLibContract.decay(curve, startAmount, decayStartBlock);
    }

    function testDutchOverflowDecay() public {
        uint256 decayStartBlock = 100;
        uint256 startAmount = 1 ether;
        int256 decayAmount = -(2**255-1);
        NonLinearDecay memory curve = NonLinearDecay({
            relativeBlocks: Util.packUint16Array(ArrayBuilder.fillUint16(1, 100)),
            relativeAmount: ArrayBuilder.fillInt(1, decayAmount)
        });
        vm.roll(150);
        vm.expectRevert();
        mockNonLinearDutchDecayLibContract.decay(curve, startAmount, decayStartBlock);
    }
}
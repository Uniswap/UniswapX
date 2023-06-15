// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DutchDecayLib} from "../../src/lib/DutchDecayLib.sol";

contract DutchDecayLibTest is Test {
    function testDutchDecayNoDecay(uint256 amount, uint256 decayStartTime, uint256 decayEndTime) public {
        vm.assume(decayEndTime >= decayStartTime);
        assertEq(DutchDecayLib.decay(amount, amount, decayStartTime, decayEndTime), amount);
    }

    function testDutchDecayNoDecayYet() public {
        vm.warp(100);
        // at decayStartTime
        assertEq(DutchDecayLib.decay(1 ether, 2 ether, 100, 200), 1 ether);

        vm.warp(80);
        // before decayStartTime
        assertEq(DutchDecayLib.decay(1 ether, 2 ether, 100, 200), 1 ether);
    }

    function testDutchDecayNoDecayYetNegative() public {
        vm.warp(100);
        // at decayStartTime
        assertEq(DutchDecayLib.decay(2 ether, 1 ether, 100, 200), 2 ether);

        vm.warp(80);
        // before decayStartTime
        assertEq(DutchDecayLib.decay(2 ether, 1 ether, 100, 200), 2 ether);
    }

    function testDutchDecay() public {
        vm.warp(150);
        assertEq(DutchDecayLib.decay(1 ether, 2 ether, 100, 200), 1.5 ether);

        vm.warp(180);
        assertEq(DutchDecayLib.decay(1 ether, 2 ether, 100, 200), 1.8 ether);

        vm.warp(110);
        assertEq(DutchDecayLib.decay(1 ether, 2 ether, 100, 200), 1.1 ether);

        vm.warp(190);
        assertEq(DutchDecayLib.decay(1 ether, 2 ether, 100, 200), 1.9 ether);
    }

    function testDutchDecayNegative() public {
        vm.warp(150);
        assertEq(DutchDecayLib.decay(2 ether, 1 ether, 100, 200), 1.5 ether);

        vm.warp(180);
        assertEq(DutchDecayLib.decay(2 ether, 1 ether, 100, 200), 1.2 ether);

        vm.warp(110);
        assertEq(DutchDecayLib.decay(2 ether, 1 ether, 100, 200), 1.9 ether);

        vm.warp(190);
        assertEq(DutchDecayLib.decay(2 ether, 1 ether, 100, 200), 1.1 ether);
    }

    function testDutchDecayFullyDecayed() public {
        vm.warp(200);
        assertEq(DutchDecayLib.decay(1 ether, 2 ether, 100, 200), 2 ether);

        vm.warp(250);
        assertEq(DutchDecayLib.decay(1 ether, 2 ether, 100, 200), 2 ether);
    }

    function testDutchDecayFullyDecayedNegative() public {
        vm.warp(200);
        assertEq(DutchDecayLib.decay(2 ether, 1 ether, 100, 200), 1 ether);

        vm.warp(250);
        assertEq(DutchDecayLib.decay(2 ether, 1 ether, 100, 200), 1 ether);
    }

    function testDutchDecayBounded(uint256 startAmount, uint256 endAmount, uint256 decayStartTime, uint256 decayEndTime)
        public
    {
        vm.assume(endAmount > startAmount);
        vm.assume(decayEndTime >= decayStartTime);
        uint256 decayed = DutchDecayLib.decay(startAmount, endAmount, decayStartTime, decayEndTime);
        assertGe(decayed, startAmount);
        assertLe(decayed, endAmount);
    }

    function testDutchDecayNegative(
        uint256 startAmount,
        uint256 endAmount,
        uint256 decayStartTime,
        uint256 decayEndTime
    ) public {
        vm.assume(endAmount < startAmount);
        vm.assume(decayEndTime >= decayStartTime);
        uint256 decayed = DutchDecayLib.decay(startAmount, endAmount, decayStartTime, decayEndTime);
        assertLe(decayed, startAmount);
        assertGe(decayed, endAmount);
    }

    function testDutchDecayInvalidTimes(
        uint256 startAmount,
        uint256 endAmount,
        uint256 decayStartTime,
        uint256 decayEndTime
    ) public {
        vm.assume(decayEndTime < decayStartTime);
        vm.expectRevert(DutchDecayLib.EndTimeBeforeStartTime.selector);
        DutchDecayLib.decay(startAmount, endAmount, decayStartTime, decayEndTime);
    }
}

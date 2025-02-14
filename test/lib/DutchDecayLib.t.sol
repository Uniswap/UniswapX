// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DutchDecayLib} from "../../src/lib/DutchDecayLib.sol";

contract DutchDecayLibTest is Test {
    function testDutchDecayNoDecay(uint256 amount, uint256 decayStartTime, uint256 decayEndTime) public {
        vm.assume(decayEndTime > decayStartTime);
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

    function testDutchDecayBounded(int256 startAmount, int256 endAmount, uint256 decayStartTime, uint256 decayEndTime)
        public
    {
        vm.assume(startAmount >= 0);
        vm.assume(endAmount > startAmount);
        vm.assume(decayEndTime > decayStartTime);
        uint256 decayed = DutchDecayLib.decay(uint256(startAmount), uint256(endAmount), decayStartTime, decayEndTime);
        assertGe(decayed, uint256(startAmount));
        assertLe(decayed, uint256(endAmount));
    }

    function testDutchDecayNegative(int256 startAmount, int256 endAmount, uint256 decayStartTime, uint256 decayEndTime)
        public
    {
        vm.assume(endAmount >= 0);
        vm.assume(endAmount < startAmount);
        vm.assume(decayEndTime > decayStartTime);
        uint256 decayed = DutchDecayLib.decay(uint256(startAmount), uint256(endAmount), decayStartTime, decayEndTime);
        assertLe(decayed, uint256(startAmount));
        assertGe(decayed, uint256(endAmount));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testDutchDecayInvalidTimes(
        uint256 startAmount,
        uint256 endAmount,
        uint256 decayStartTime,
        uint256 decayEndTime
    ) public {
        vm.assume(startAmount != endAmount);
        vm.assume(decayEndTime < decayStartTime);
        vm.expectRevert(DutchDecayLib.EndTimeBeforeStartTime.selector);
        DutchDecayLib.decay(startAmount, endAmount, decayStartTime, decayEndTime);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testDutchDownwardDecayOverflow() public {
        vm.expectRevert();
        DutchDecayLib.linearDecay(0, 100, 99, type(int256).max, -1);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testDutchUpwardDecayOverflow() public {
        vm.expectRevert();
        DutchDecayLib.linearDecay(0, 100, 99, -1, type(int256).max);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testDutchDecayDivByZero() public {
        vm.expectRevert();
        DutchDecayLib.linearDecay(100, 100, 99, 1, -1);
    }
}

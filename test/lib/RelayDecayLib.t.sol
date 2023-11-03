// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {RelayDecayLib} from "../../src/lib/RelayDecayLib.sol";

contract RelayDecayLibTest is Test {
    function testRelayDecayNoDecay(uint256 amount, uint256 decayStartTime, uint256 decayEndTime) public {
        vm.assume(decayEndTime >= decayStartTime);
        assertEq(RelayDecayLib.decay(amount, amount, decayStartTime, decayEndTime), amount);
    }

    function testRelayDecayNoDecayYet() public {
        vm.warp(100);
        // at decayStartTime
        assertEq(RelayDecayLib.decay(1 ether, 2 ether, 100, 200), 1 ether);

        vm.warp(80);
        // before decayStartTime
        assertEq(RelayDecayLib.decay(1 ether, 2 ether, 100, 200), 1 ether);
    }

    function testRelayDecayNoDecayYetNegative() public {
        vm.warp(100);
        // at decayStartTime
        assertEq(RelayDecayLib.decay(2 ether, 1 ether, 100, 200), 2 ether);

        vm.warp(80);
        // before decayStartTime
        assertEq(RelayDecayLib.decay(2 ether, 1 ether, 100, 200), 2 ether);
    }

    function testRelayDecay() public {
        vm.warp(150);
        assertEq(RelayDecayLib.decay(1 ether, 2 ether, 100, 200), 1.5 ether);

        vm.warp(180);
        assertEq(RelayDecayLib.decay(1 ether, 2 ether, 100, 200), 1.8 ether);

        vm.warp(110);
        assertEq(RelayDecayLib.decay(1 ether, 2 ether, 100, 200), 1.1 ether);

        vm.warp(190);
        assertEq(RelayDecayLib.decay(1 ether, 2 ether, 100, 200), 1.9 ether);
    }

    function testRelayDecayNegative() public {
        vm.warp(150);
        assertEq(RelayDecayLib.decay(2 ether, 1 ether, 100, 200), 1.5 ether);

        vm.warp(180);
        assertEq(RelayDecayLib.decay(2 ether, 1 ether, 100, 200), 1.2 ether);

        vm.warp(110);
        assertEq(RelayDecayLib.decay(2 ether, 1 ether, 100, 200), 1.9 ether);

        vm.warp(190);
        assertEq(RelayDecayLib.decay(2 ether, 1 ether, 100, 200), 1.1 ether);
    }

    function testRelayDecayFullyDecayed() public {
        vm.warp(200);
        assertEq(RelayDecayLib.decay(1 ether, 2 ether, 100, 200), 2 ether);

        vm.warp(250);
        assertEq(RelayDecayLib.decay(1 ether, 2 ether, 100, 200), 2 ether);
    }

    function testRelayDecayFullyDecayedNegative() public {
        vm.warp(200);
        assertEq(RelayDecayLib.decay(2 ether, 1 ether, 100, 200), 1 ether);

        vm.warp(250);
        assertEq(RelayDecayLib.decay(2 ether, 1 ether, 100, 200), 1 ether);
    }

    function testRelayDecayBounded(uint256 startAmount, uint256 endAmount, uint256 decayStartTime, uint256 decayEndTime)
        public
    {
        vm.assume(endAmount > startAmount);
        vm.assume(decayEndTime >= decayStartTime);
        uint256 decayed = RelayDecayLib.decay(startAmount, endAmount, decayStartTime, decayEndTime);
        assertGe(decayed, startAmount);
        assertLe(decayed, endAmount);
    }

    function testRelayDecayNegative(
        uint256 startAmount,
        uint256 endAmount,
        uint256 decayStartTime,
        uint256 decayEndTime
    ) public {
        vm.assume(endAmount < startAmount);
        vm.assume(decayEndTime >= decayStartTime);
        uint256 decayed = RelayDecayLib.decay(startAmount, endAmount, decayStartTime, decayEndTime);
        assertLe(decayed, startAmount);
        assertGe(decayed, endAmount);
    }

    function testRelayDecayInvalidTimes(
        uint256 startAmount,
        uint256 endAmount,
        uint256 decayStartTime,
        uint256 decayEndTime
    ) public {
        vm.assume(decayEndTime < decayStartTime);
        vm.expectRevert(RelayDecayLib.EndTimeBeforeStartTime.selector);
        RelayDecayLib.decay(startAmount, endAmount, decayStartTime, decayEndTime);
    }
}

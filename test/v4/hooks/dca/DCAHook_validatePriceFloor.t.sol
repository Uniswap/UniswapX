// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../../../util/DeployPermit2.sol";
import {DCAHookHarness} from "./DCAHookHarness.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";
import {IDCAHook} from "../../../../src/v4/interfaces/IDCAHook.sol";

contract DCAHook_validatePriceFloorTest is Test, DeployPermit2 {
    DCAHookHarness hook;
    IPermit2 permit2;
    address constant REACTOR_ADDRESS = address(0x2345);
    IReactor constant REACTOR = IReactor(REACTOR_ADDRESS);

    uint256 constant MIN_PRICE_1_TO_1 = 1e18;
    uint256 constant MIN_PRICE_2_TO_1 = 2e18;
    uint256 constant MIN_PRICE_HALF = 0.5e18;
    uint256 constant MIN_PRICE_ZERO = 0;

    function setUp() public {
        permit2 = IPermit2(deployPermit2());
        hook = new DCAHookHarness(permit2, REACTOR);
    }

    // ============ EXACT_IN Tests ============

    function test_validatePriceFloor_exactIn_success_noPriceFloor() public view {
        hook.validatePriceFloor(true, 100e18, 50e18, MIN_PRICE_ZERO);
    }

    function test_validatePriceFloor_exactIn_success_atExactMinPrice() public view {
        // Price = output/input = 100/100 = 1.0
        hook.validatePriceFloor(true, 100e18, 100e18, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactIn_success_aboveMinPrice() public view {
        // Price = output/input = 200/100 = 2.0, min = 1.0
        hook.validatePriceFloor(true, 100e18, 200e18, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactIn_revert_belowMinPrice() public {
        // Price = output/input = 50/100 = 0.5, min = 1.0
        uint256 actualPrice = (50e18 * 1e18) / 100e18;
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.PriceBelowMin.selector, actualPrice, MIN_PRICE_1_TO_1));
        hook.validatePriceFloor(true, 100e18, 50e18, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactIn_revert_justBelowMinPrice() public {
        // Price = 99.999.../100 < 1.0
        uint256 limitAmount = 99999999999999999999;
        uint256 actualPrice = (limitAmount * 1e18) / 100e18;
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.PriceBelowMin.selector, actualPrice, MIN_PRICE_1_TO_1));
        hook.validatePriceFloor(true, 100e18, uint160(limitAmount), MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactIn_success_largeNumbers() public view {
        uint160 execAmount = 1000000e18;
        uint160 limitAmount = 2000000e18;
        // Price = 2000000/1000000 = 2.0, min = 1.5
        hook.validatePriceFloor(true, execAmount, limitAmount, 1.5e18);
    }

    function test_validatePriceFloor_exactIn_success_smallNumbers() public view {
        // Price = 2/1 = 2.0, min = 1.0
        hook.validatePriceFloor(true, 1, 2, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactIn_revert_zeroInput() public {
        vm.expectRevert();
        hook.validatePriceFloor(true, 0, 100e18, MIN_PRICE_1_TO_1);
    }

    // ============ EXACT_OUT Tests ============

    function test_validatePriceFloor_exactOut_success_noPriceFloor() public view {
        hook.validatePriceFloor(false, 100e18, 200e18, MIN_PRICE_ZERO);
    }

    function test_validatePriceFloor_exactOut_success_atExactMinPrice() public view {
        // Price = output/input = 100/100 = 1.0
        hook.validatePriceFloor(false, 100e18, 100e18, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactOut_success_aboveMinPrice() public view {
        // Price = output/input = 100/50 = 2.0, min = 1.0
        hook.validatePriceFloor(false, 100e18, 50e18, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactOut_revert_belowMinPrice() public {
        // Price = output/input = 100/200 = 0.5, min = 1.0
        uint256 actualPrice = (100e18 * 1e18) / 200e18;
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.PriceBelowMin.selector, actualPrice, MIN_PRICE_1_TO_1));
        hook.validatePriceFloor(false, 100e18, 200e18, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactOut_revert_justBelowMinPrice() public {
        // Price = 100/100.000...01 < 1.0
        uint256 limitAmount = 100000000000000000001;
        uint256 actualPrice = (100e18 * 1e18) / limitAmount;
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.PriceBelowMin.selector, actualPrice, MIN_PRICE_1_TO_1));
        hook.validatePriceFloor(false, 100e18, uint160(limitAmount), MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactOut_success_largeNumbers() public view {
        uint160 execAmount = 1000000e18;
        uint160 limitAmount = 500000e18;
        // Price = 1000000/500000 = 2.0, min = 1.5
        hook.validatePriceFloor(false, execAmount, limitAmount, 1.5e18);
    }

    function test_validatePriceFloor_exactOut_success_smallNumbers() public view {
        // Price = 2/1 = 2.0, min = 1.0
        hook.validatePriceFloor(false, 2, 1, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactOut_revert_zeroInput() public {
        vm.expectRevert();
        hook.validatePriceFloor(false, 100e18, 0, MIN_PRICE_1_TO_1);
    }

    // ============ Fuzz Tests ============

    function testFuzz_validatePriceFloor_exactIn_success(uint160 execAmount, uint160 limitAmount, uint256 minPrice)
        public
        view
    {
        vm.assume(execAmount > 0 && execAmount <= type(uint160).max);
        vm.assume(limitAmount > 0 && limitAmount <= type(uint160).max);
        vm.assume(minPrice <= 1e36); // Reasonable price range

        // Calculate actual price
        uint256 actualPrice = (uint256(limitAmount) * 1e18) / uint256(execAmount);

        // Only test cases where price >= minPrice
        vm.assume(actualPrice >= minPrice);

        hook.validatePriceFloor(true, execAmount, limitAmount, minPrice);
    }

    function testFuzz_validatePriceFloor_exactIn_revert(uint160 execAmount, uint160 limitAmount, uint256 minPrice)
        public
    {
        vm.assume(execAmount > 0 && execAmount <= type(uint160).max);
        vm.assume(limitAmount > 0 && limitAmount <= type(uint160).max);
        vm.assume(minPrice > 0 && minPrice <= 1e36);

        // Calculate actual price
        uint256 actualPrice = (uint256(limitAmount) * 1e18) / uint256(execAmount);

        // Only test cases where price < minPrice
        vm.assume(actualPrice < minPrice);

        vm.expectRevert();
        hook.validatePriceFloor(true, execAmount, limitAmount, minPrice);
    }

    function testFuzz_validatePriceFloor_exactOut_success(uint160 execAmount, uint160 limitAmount, uint256 minPrice)
        public
        view
    {
        vm.assume(execAmount > 0 && execAmount <= type(uint160).max);
        vm.assume(limitAmount > 0 && limitAmount <= type(uint160).max);
        vm.assume(minPrice <= 1e36);

        // Calculate actual price
        uint256 actualPrice = (uint256(execAmount) * 1e18) / uint256(limitAmount);

        // Only test cases where price >= minPrice
        vm.assume(actualPrice >= minPrice);

        hook.validatePriceFloor(false, execAmount, limitAmount, minPrice);
    }

    function testFuzz_validatePriceFloor_exactOut_revert(uint160 execAmount, uint160 limitAmount, uint256 minPrice)
        public
    {
        vm.assume(execAmount > 0 && execAmount <= type(uint160).max);
        vm.assume(limitAmount > 0 && limitAmount <= type(uint160).max);
        vm.assume(minPrice > 0 && minPrice <= 1e36);

        // Calculate actual price
        uint256 actualPrice = (uint256(execAmount) * 1e18) / uint256(limitAmount);

        // Only test cases where price < minPrice
        vm.assume(actualPrice < minPrice);

        vm.expectRevert();
        hook.validatePriceFloor(false, execAmount, limitAmount, minPrice);
    }

    // ============ Edge Cases ============

    function test_validatePriceFloor_exactIn_maxValues() public view {
        uint160 maxUint160 = type(uint160).max;
        // Price = max/max = 1.0
        hook.validatePriceFloor(true, maxUint160, maxUint160, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactOut_maxValues() public view {
        uint160 maxUint160 = type(uint160).max;
        // Price = max/max = 1.0
        hook.validatePriceFloor(false, maxUint160, maxUint160, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactIn_overflow_protection() public view {
        uint160 execAmount = 1;
        uint160 limitAmount = type(uint160).max;
        // This should handle overflow gracefully
        // Price = max/1 = very high, min = 1.0
        hook.validatePriceFloor(true, execAmount, limitAmount, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_exactOut_overflow_protection() public view {
        uint160 execAmount = type(uint160).max;
        uint160 limitAmount = 1;
        // Price = max/1 = very high, min = 1.0
        hook.validatePriceFloor(false, execAmount, limitAmount, MIN_PRICE_1_TO_1);
    }

    function test_validatePriceFloor_precision_18Decimals() public view {
        // Testing with 18 decimal precision
        uint160 execAmount = 1234567890123456789;
        uint160 limitAmount = 2469135780246913578;
        // Price = exactly 2.0
        hook.validatePriceFloor(true, execAmount, limitAmount, MIN_PRICE_2_TO_1);
    }

    function test_validatePriceFloor_precision_nonStandardDecimals() public view {
        // USDC-like (6 decimals) to WETH-like (18 decimals)
        uint160 execAmount = 1000 * 1e6; // 1000 USDC
        uint160 limitAmount = 1 * 1e18; // 1 WETH
        uint256 minPrice = 1000 * 1e18; // 1 WETH = 1000 USDC

        // Price = (1e18 * 1e18) / (1000 * 1e6) = 1e30 / 1e9 = 1e21 = 1000 * 1e18
        hook.validatePriceFloor(true, execAmount, limitAmount, minPrice);
    }
}

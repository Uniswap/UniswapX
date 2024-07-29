// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {PriorityInput, PriorityOutput} from "../../src/lib/PriorityOrderLib.sol";
import {PriorityFeeLib} from "../../src/lib/PriorityFeeLib.sol";

contract PriorityFeeLibTest is Test {
    using FixedPointMathLib for uint256;

    uint256 constant MPS = 1e7;
    /// 1.111111111111111111 ether (for testing precision)
    uint256 constant amount = 1111111111111111111;

    function setUp() public view {
        assertEq(block.basefee, 0);
    }

    function testScaleInputNoPriorityFee() public view {
        assertEq(tx.gasprice, 0);

        PriorityInput memory input =
            PriorityInput({token: ERC20(address(0)), amount: amount, mpsPerPriorityFeeWei: 100});

        InputToken memory scaledInput = PriorityFeeLib.scale(input, tx.gasprice);
        assertEq(scaledInput.amount, input.amount);
        assertEq(scaledInput.maxAmount, input.amount);
    }

    function testScaleOutputNoPriorityFee() public view {
        assertEq(tx.gasprice, 0);

        PriorityOutput memory output =
            PriorityOutput({token: address(0), amount: amount, mpsPerPriorityFeeWei: 100, recipient: address(0)});

        OutputToken memory scaledOutput = PriorityFeeLib.scale(output, tx.gasprice);
        assertEq(scaledOutput.amount, output.amount);
    }

    function testScaleInputLowPriorityFee() public {
        uint256 priorityFee = 1;
        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);

        PriorityInput memory input = PriorityInput({token: ERC20(address(0)), amount: amount, mpsPerPriorityFeeWei: 1});
        InputToken memory scaledInput = PriorityFeeLib.scale(input, tx.gasprice);
        uint256 scaledAmount = input.amount.mulDivDown((MPS - tx.gasprice * input.mpsPerPriorityFeeWei), MPS);
        assertEq(scaledInput.amount, scaledAmount);
        assertEq(scaledInput.maxAmount, input.amount);
    }

    function testScaleInputPriorityFeeOverMax() public {
        uint256 priorityFee = MPS + 1;
        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);

        PriorityInput memory input = PriorityInput({token: ERC20(address(0)), amount: amount, mpsPerPriorityFeeWei: 1});

        InputToken memory scaledInput = PriorityFeeLib.scale(input, tx.gasprice);
        assertEq(scaledInput.amount, 0);
        assertEq(scaledInput.maxAmount, input.amount);
    }

    function testScaleInputPriorityFee_fuzz(uint256 priorityFee) public {
        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);

        PriorityInput memory input = PriorityInput({token: ERC20(address(0)), amount: amount, mpsPerPriorityFeeWei: 1});

        InputToken memory scaledInput = PriorityFeeLib.scale(input, tx.gasprice);

        uint256 scaledAmount;
        if (tx.gasprice * input.mpsPerPriorityFeeWei < MPS) {
            scaledAmount = input.amount.mulDivDown((MPS - tx.gasprice * input.mpsPerPriorityFeeWei), MPS);
        }

        assertEq(scaledInput.amount, scaledAmount);
        assertEq(scaledInput.maxAmount, input.amount);
    }

    function testScaleOutputLowPriorityFee() public {
        uint256 priorityFee = 1;
        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);

        PriorityOutput memory output =
            PriorityOutput({token: address(0), amount: amount, mpsPerPriorityFeeWei: 1, recipient: address(0)});
        OutputToken memory scaledOutput = PriorityFeeLib.scale(output, tx.gasprice);
        uint256 scaledAmount = output.amount.mulDivUp((MPS + tx.gasprice * output.mpsPerPriorityFeeWei), MPS);
        assertEq(scaledOutput.amount, scaledAmount);
    }

    /// @notice if the amount to scale is large enough to cause a phantom overflow in mulDivUp, we expect a revert
    function testScaleRevertsOnLargeOutput() public {
        uint256 priorityFee = 0;
        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);

        uint256 largeAmount = type(uint256).max / MPS + 1;

        PriorityOutput memory output =
            PriorityOutput({token: address(0), amount: largeAmount, mpsPerPriorityFeeWei: 1, recipient: address(0)});

        vm.expectRevert();
        PriorityFeeLib.scale(output, tx.gasprice);
    }

    function testScaleOutputPriorityFee_fuzz(uint256 priorityFee, uint256 mpsPerPriorityFeeWei) public {
        // the amount of MPS to scale the output by
        uint256 scalingFactor = MPS;
        // overflows can happen when the priority fee is too high, or when the mpsPerPriorityFeeWei is too high
        // we call their product scalingFactor here, and for thes test setup, we ensure that MPS + scalingFactor < type(uint256).max
        bool scalingFactorOverflow;
        unchecked {
            if (priorityFee != 0 && mpsPerPriorityFeeWei != 0) {
                uint256 temp = priorityFee * mpsPerPriorityFeeWei;
                scalingFactorOverflow = temp / mpsPerPriorityFeeWei != priorityFee;
                scalingFactorOverflow = scalingFactorOverflow || MPS + temp < MPS;
                scalingFactor = MPS + temp;
            }
        }
        vm.assume(!scalingFactorOverflow);

        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);

        PriorityOutput memory output = PriorityOutput({
            token: address(0),
            amount: amount,
            mpsPerPriorityFeeWei: mpsPerPriorityFeeWei,
            recipient: address(0)
        });

        OutputToken memory scaledOutput;

        // if the scaling factor is large but valid (i.e. it doesn't overflow), we should expect the library to
        // revert if the product between it and the output amount overflows
        // we detect if that will happen here and expect a revert for those test cases
        bool willOverflow;
        unchecked {
            willOverflow = (output.amount * scalingFactor) / scalingFactor != output.amount;
        }

        if (willOverflow) {
            vm.expectRevert();
            scaledOutput = PriorityFeeLib.scale(output, tx.gasprice);
        } else {
            scaledOutput = PriorityFeeLib.scale(output, tx.gasprice);
            // Ensure that it rounds up
            uint256 scaledAmount = output.amount.mulDivUp(scalingFactor, MPS);
            assertEq(scaledOutput.amount, scaledAmount);
        }
    }

    /// @notice no scaling should be done when the mpsPerPriorityFeeWei is 0
    function testScaleInputWithZeroMpsPerPriorityFeeWei_fuzz(uint256 priorityFee) public {
        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);
        PriorityInput memory input = PriorityInput({token: ERC20(address(0)), amount: amount, mpsPerPriorityFeeWei: 0});

        InputToken memory scaledInput = PriorityFeeLib.scale(input, tx.gasprice);
        assertEq(scaledInput.amount, input.amount);
        assertEq(scaledInput.maxAmount, input.amount);
    }

    /// @notice no scaling should be done when the mpsPerPriorityFeeWei is 0
    function testScaleOutputWithZeroMpsPerPriorityFeeWei_fuzz(uint256 priorityFee) public {
        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);
        PriorityOutput memory output =
            PriorityOutput({token: address(0), amount: amount, mpsPerPriorityFeeWei: 0, recipient: address(0)});

        OutputToken memory scaledOutput = PriorityFeeLib.scale(output, tx.gasprice);
        assertEq(scaledOutput.amount, output.amount);
    }
}

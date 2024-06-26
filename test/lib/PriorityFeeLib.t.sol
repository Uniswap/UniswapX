// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {PriorityInput, PriorityOutput} from "../../src/lib/PriorityOrderLib.sol";
import {PriorityFeeLib} from "../../src/lib/PriorityFeeLib.sol";

// base fee is 0 by default
contract PriorityFeeLibTest is Test {
    uint256 constant MPS = 1e7;

    function testScaleInputNoPriorityFee() public {
        assertEq(tx.gasprice, 0);

        PriorityInput memory input =
            PriorityInput({token: ERC20(address(0)), amount: 1 ether, mpsPerPriorityFeeWei: 100});

        uint256 scaledAmount = (input.amount * (MPS - tx.gasprice * input.mpsPerPriorityFeeWei)) / MPS;

        InputToken memory scaledInput = PriorityFeeLib.scale(input, tx.gasprice);
        assertEq(scaledInput.amount, scaledAmount);
        assertEq(scaledInput.maxAmount, scaledAmount);
    }

    function testScaleOutputNoPriorityFee() public {
        assertEq(tx.gasprice, 0);

        PriorityOutput memory output =
            PriorityOutput({token: address(0), amount: 1 ether, mpsPerPriorityFeeWei: 100, recipient: address(0)});

        OutputToken memory scaledOutput = PriorityFeeLib.scale(output, tx.gasprice);
        uint256 scaledAmount = (output.amount * (MPS + tx.gasprice * output.mpsPerPriorityFeeWei)) / MPS;

        assertEq(scaledOutput.amount, scaledAmount);
    }

    function testScaleInputPriorityFee_fuzz(uint256 priorityFee) public {
        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);

        PriorityInput memory input = PriorityInput({token: ERC20(address(0)), amount: 1 ether, mpsPerPriorityFeeWei: 1});

        InputToken memory scaledInput = PriorityFeeLib.scale(input, tx.gasprice);

        uint256 scaledAmount;
        if (tx.gasprice * input.mpsPerPriorityFeeWei < MPS) {
            scaledAmount = (input.amount * (MPS - tx.gasprice * input.mpsPerPriorityFeeWei)) / MPS;
        }

        assertEq(scaledInput.amount, scaledAmount);
        assertEq(scaledInput.maxAmount, scaledAmount);
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
            amount: 1 ether,
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
            uint256 scaledAmount = (output.amount * (MPS + tx.gasprice * output.mpsPerPriorityFeeWei)) / MPS;
            assertEq(scaledOutput.amount, scaledAmount);
        }
    }
}

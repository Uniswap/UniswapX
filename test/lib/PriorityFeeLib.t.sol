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
    uint256 constant PPS = 1e10;

    function testScaleInputNoPriorityFee() public {
        assertEq(tx.gasprice, 0);

        PriorityInput memory input =
            PriorityInput({token: ERC20(address(0)), amount: 1 ether, pipsPerPriorityFeeWei: 100});

        uint256 scaledAmount = (input.amount * (PPS - tx.gasprice * input.pipsPerPriorityFeeWei)) / PPS;

        InputToken memory scaledInput = PriorityFeeLib.scale(input, tx.gasprice);
        assertEq(scaledInput.amount, scaledAmount);
        assertEq(scaledInput.maxAmount, scaledAmount);
    }

    function testScaleOutputNoPriorityFee() public {
        assertEq(tx.gasprice, 0);

        PriorityOutput memory output =
            PriorityOutput({token: address(0), amount: 1 ether, pipsPerPriorityFeeWei: 100, recipient: address(0)});

        OutputToken memory scaledOutput = PriorityFeeLib.scale(output, tx.gasprice);
        uint256 scaledAmount = (output.amount * (PPS + tx.gasprice * output.pipsPerPriorityFeeWei)) / PPS;

        assertEq(scaledOutput.amount, scaledAmount);
    }

    function testScaleInputPriorityFee_fuzz(uint256 priorityFee) public {
        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);

        PriorityInput memory input = PriorityInput({token: ERC20(address(0)), amount: 1 ether, pipsPerPriorityFeeWei: 1});

        InputToken memory scaledInput = PriorityFeeLib.scale(input, tx.gasprice);

        uint256 scaledAmount;
        if (tx.gasprice * input.pipsPerPriorityFeeWei < PPS) {
            scaledAmount = (input.amount * (PPS - tx.gasprice * input.pipsPerPriorityFeeWei)) / PPS;
        }

        assertEq(scaledInput.amount, scaledAmount);
        assertEq(scaledInput.maxAmount, scaledAmount);
    }

    function testScaleOutputPriorityFee_fuzz(uint256 priorityFee, uint256 pipsPerPriorityFeeWei) public {
        // the amount of PPS to scale the output by
        uint256 scalingFactor = PPS;
        // overflows can happen when the priority fee is too high, or when the pipsPerPriorityFeeWei is too high
        // we call their product scalingFactor here, and for thes test setup, we ensure that PPS + scalingFactor < type(uint256).max
        bool scalingFactorOverflow;
        unchecked {
            if (priorityFee != 0 && pipsPerPriorityFeeWei != 0) {
                uint256 temp = priorityFee * pipsPerPriorityFeeWei;
                scalingFactorOverflow = temp / pipsPerPriorityFeeWei != priorityFee;
                scalingFactorOverflow = scalingFactorOverflow || PPS + temp < PPS;
                scalingFactor = PPS + temp;
            }
        }
        vm.assume(!scalingFactorOverflow);

        vm.txGasPrice(priorityFee);
        assertEq(tx.gasprice, priorityFee);

        PriorityOutput memory output = PriorityOutput({
            token: address(0),
            amount: 1 ether,
            pipsPerPriorityFeeWei: pipsPerPriorityFeeWei,
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
            uint256 scaledAmount = (output.amount * (PPS + tx.gasprice * output.pipsPerPriorityFeeWei)) / PPS;
            assertEq(scaledOutput.amount, scaledAmount);
        }
    }
}

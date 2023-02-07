// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchInput} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {IPSFees} from "../../src/base/IPSFees.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchLimitOrder, DutchLimitOrderLib, DutchOutput} from "../../src/lib/DutchLimitOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ExclusiveFillerValidation} from "../../src/sample-validation-contracts/ExclusiveFillerValidation.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

contract ExclusiveFillerValidationTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using DutchLimitOrderLib for DutchLimitOrder;

    address constant PROTOCOL_FEE_RECIPIENT = address(1);
    uint256 constant PROTOCOL_FEE_BPS = 500;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 makerPrivateKey;
    address maker;
    DutchLimitOrderReactor reactor;
    ISignatureTransfer permit2;
    ExclusiveFillerValidation exclusiveFillerValidation;

    function setUp() public {
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        permit2 = ISignatureTransfer(deployPermit2());
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        exclusiveFillerValidation = new ExclusiveFillerValidation();
    }

    // Test exclusive filler validation contract succeeds
    function testExclusiveFillerSucceeds() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp + 50, 0)
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        // Below snapshot can be compared to `DutchExecuteSingle.snap` to compare an execute with and without
        // exclusive filler validation
        snapStart("testExclusiveFillerSucceeds");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        snapEnd();
        assertEq(tokenOut.balanceOf(maker), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    // The filler is incorrectly address(0x123)
    function testNonExclusiveFillerFails() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp + 50, 0)
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        vm.prank(address(0x123));
        vm.expectRevert(ExclusiveFillerValidation.ValidationFailed.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
    }

    // Ensure a different filler (not the one encoded in validationData) is able to execute after last exclusive
    // timestamp
    function testNonExclusiveFillerSucceedsPastExclusiveTimestamp() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        vm.warp(1000);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp - 50, 0)
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        vm.prank(address(0x123));
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenOut.balanceOf(maker), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    // Test non exclusive filler cannot fill exactly on last exclusive timestamp
    function testNonExclusiveFillerFailsOnLastExclusiveTimestamp() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp, 0)
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        vm.prank(address(0x123));
        vm.expectRevert(ExclusiveFillerValidation.ValidationFailed.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
    }

    // Test non exclusive filler can fill an exclusiver order by overriding output amount
    function testNonExclusiveFillerFillsWithOverride() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount * 101 / 100);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation))
                // override increase set to 100 bps, so filler must pay 1% more output
                .withValidationData(abi.encode(address(0x80085), block.timestamp + 50, 100)),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenOut.balanceOf(maker), outputAmount * 101 / 100);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    // Order has a 1% override, but the fillContract has insufficient funds. Block timestamp is prior to
    // `lastExclusiveTimestamp` so this test will revert.
    function testNonExclusiveFillerFailsWithOverrideIfInsufficientOutput() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation))
                // override increase set to 100 bps, so filler must pay 1% more output
                .withValidationData(abi.encode(address(0x80085), block.timestamp + 50, 100)),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        vm.expectRevert("TRANSFER_FROM_FAILED");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
    }

    // Order has a 1% override, but fillContract only has enough funds for the original unadjusted output amount.
    // Block timestamp is after to `lastExclusiveTimestamp` so filler will still succeed.
    function testNonExclusiveFillerSucceedsWithOverrideIfPastLastExclusiveTimestamp() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        vm.warp(1000);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation))
                // override increase set to 100 bps, so filler must pay 1% more output
                .withValidationData(abi.encode(address(0x80085), block.timestamp - 50, 100)),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenOut.balanceOf(maker), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    // Test that a non exclusive filler succeeds with 1% output override, output decay, and a fee.
    function testNonExclusiveFillerSucceedsWithOverrideIncludingFeesAndDecay() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount * 2);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        vm.warp(1000);
        DutchOutput[] memory outputsWithFeeAndDecay = new DutchOutput[](2);
        outputsWithFeeAndDecay[0] = DutchOutput(address(tokenOut), outputAmount, outputAmount * 9 / 10, maker, false);
        outputsWithFeeAndDecay[1] =
            DutchOutput(address(tokenOut), outputAmount / 20, outputAmount * 9 / 200, maker, true);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation))
                // override increase set to 100 bps, so filler must pay 1% more output
                .withValidationData(abi.encode(address(0x80085), block.timestamp + 50, 100)),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: outputsWithFeeAndDecay
        });

        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        // Output decay reduces output amount by 5%. RFQ override increases output amount by 1%
        uint256 adjustedOutputAmount = outputAmount * 95 / 100 * 101 / 100;
        assertEq(tokenOut.balanceOf(maker), adjustedOutputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), 2 * outputAmount - (adjustedOutputAmount * 21 / 20));
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        // Fees collected are 5% of 1st output, and will remain in the reactor
        assertEq(tokenOut.balanceOf(address(reactor)), adjustedOutputAmount / 20);
        // 5% of the fee will go to protocol
        assertEq(IPSFees(address(reactor)).feesOwed(address(tokenOut), address(0)), adjustedOutputAmount / 20 / 20);
        // 95% of the fee will go to interface (we set to maker in this case)
        assertEq(IPSFees(address(reactor)).feesOwed(address(tokenOut), maker), adjustedOutputAmount / 20 * 19 / 20);
    }

    // Test that RFQ winner can fill an order with override. Use same details as the test above,
    // testNonExclusiveFillerSucceedsWithOverrideIncludingFeesAndDecay
    function testRfqWinnerSucceedsWithOverrideIncludingFeesAndDecay() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount * 2);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        vm.warp(1000);
        DutchOutput[] memory outputsWithFeeAndDecay = new DutchOutput[](2);
        outputsWithFeeAndDecay[0] = DutchOutput(address(tokenOut), outputAmount, outputAmount * 9 / 10, maker, false);
        outputsWithFeeAndDecay[1] =
            DutchOutput(address(tokenOut), outputAmount / 20, outputAmount * 9 / 200, maker, true);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation))
                // Set the RFQ winner to this contract
                .withValidationData(abi.encode(address(this), block.timestamp + 50, 100)),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: outputsWithFeeAndDecay
        });

        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        // Output decay reduces output amount by 5%
        uint256 adjustedOutputAmount = outputAmount * 95 / 100;
        assertEq(tokenOut.balanceOf(maker), adjustedOutputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), 2 * outputAmount - (adjustedOutputAmount * 21 / 20));
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        // Fees collected are 5% of 1st output, and will remain in the reactor
        assertEq(tokenOut.balanceOf(address(reactor)), adjustedOutputAmount / 20);
        // 5% of the fee will go to protocol
        assertEq(IPSFees(address(reactor)).feesOwed(address(tokenOut), address(0)), adjustedOutputAmount / 20 / 20);
        // 95% of the fee will go to interface (we set to maker in this case)
        assertEq(IPSFees(address(reactor)).feesOwed(address(tokenOut), maker), adjustedOutputAmount / 20 * 19 / 20);
    }

    // Very similar to testNonExclusiveFillerFillsWithOverride, but with input decay
    function testNonExclusiveFillerFillsWithOverrideWithInputDecay() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount * 101 / 100);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        vm.warp(1000);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation))
                // override increase set to 100 bps, so filler must pay 1% more output
                .withValidationData(abi.encode(address(0x80085), block.timestamp + 50, 100)),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount / 2, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenOut.balanceOf(maker), outputAmount * 101 / 100);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount * 3 / 4);
    }

    // Test that a revert will occur if output amount is too high and will overflow when multiplying by 10000 in
    // `BaseReactor._fill()`
    function testNonExclusiveFillerFailsWithOverrideBecauseOverflow() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = type(uint256).max / 1000;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount * 101 / 100);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation))
                // override increase set to 100 bps, so filler must pay 1% more output
                .withValidationData(abi.encode(address(0x80085), block.timestamp + 50, 100)),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        vm.expectRevert(bytes(""));
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
    }

    // Test that direct taker fill macro works with output override
    function testDirectTakerFillMacroWithOverride() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(this), outputAmount * 102 / 100);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation))
                // override increase set to 200 bps, so filler must pay 2% more output
                .withValidationData(abi.encode(address(0x80085), block.timestamp + 50, 200)),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        tokenOut.forceApprove(address(this), address(permit2), type(uint256).max);
        IAllowanceTransfer(address(permit2)).approve(
            address(tokenOut), address(reactor), type(uint160).max, type(uint48).max
        );
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)), address(1), bytes("")
        );
        assertEq(tokenOut.balanceOf(maker), outputAmount * 102 / 100);
        assertEq(tokenIn.balanceOf(address(this)), inputAmount);
    }
}

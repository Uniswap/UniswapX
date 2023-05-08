// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchInput} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchLimitOrder, DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ExclusiveFillerValidation} from "../../src/sample-validation-contracts/ExclusiveFillerValidation.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

contract ExclusiveFillerValidationTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using DutchLimitOrderLib for DutchLimitOrder;

    address constant PROTOCOL_FEE_RECIPIENT = address(1);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 swapperPrivateKey;
    address swapper;
    DutchLimitOrderReactor reactor;
    ISignatureTransfer permit2;
    ExclusiveFillerValidation exclusiveFillerValidation;

    function setUp() public {
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        permit2 = ISignatureTransfer(deployPermit2());
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        exclusiveFillerValidation = new ExclusiveFillerValidation();
    }

    // Test exclusive filler validation contract succeeds
    function testExclusiveFillerSucceeds() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp + 50)
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });

        // Below snapshot can be compared to `DutchExecuteSingle.snap` to compare an execute with and without
        // exclusive filler validation
        snapStart("testExclusiveFillerSucceeds");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        snapEnd();
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    // The filler is incorrectly address(0x123)
    function testNonExclusiveFillerFails() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp + 50)
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });

        vm.prank(address(0x123));
        vm.expectRevert(ResolvedOrderLib.ValidationFailed.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
    }

    // Ensure a different filler (not the one encoded in validationData) is able to execute after last exclusive
    // timestamp
    function testNonExclusiveFillerSucceedsPastExclusiveTimestamp() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        vm.warp(1000);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp - 50)
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });

        vm.prank(address(0x123));
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    // Test non exclusive filler cannot fill exactly on last exclusive timestamp
    function testNonExclusiveFillerFailsOnLastExclusiveTimestamp() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp)
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });

        vm.prank(address(0x123));
        vm.expectRevert(ResolvedOrderLib.ValidationFailed.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
    }
}

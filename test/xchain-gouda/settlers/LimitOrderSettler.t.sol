// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import {InputToken, SignedOrder} from "../../../src/base/ReactorStructs.sol";
import {
    ActiveSettlement,
    SettlementInfo,
    SettlementStatus,
    ResolvedOrder,
    OutputToken,
    CollateralToken
} from "../../../src/xchain-gouda/base/SettlementStructs.sol";
import {ISettlementOracle} from "../../../src/xchain-gouda/interfaces/ISettlementOracle.sol";
import {SettlementEvents} from "../../../src/xchain-gouda/base/SettlementEvents.sol";
import {MockERC20} from "../../util/mock/MockERC20.sol";
import {
    CrossChainLimitOrder, CrossChainLimitOrderLib
} from "../../../src/xchain-gouda/lib/CrossChainLimitOrderLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "../../util/DeployPermit2.sol";
import {MockValidationContract} from "../util/mock/MockValidationContract.sol";
import {MockSettlementOracle} from "../util/mock/MockSettlementOracle.sol";
import {LimitOrderSettler} from "../../../src/xchain-gouda/settlers/LimitOrderSettler.sol";
import {SettlementInfoBuilder} from "../util/SettlementInfoBuilder.sol";
import {OutputsBuilder} from "../../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract CrossChainLimitOrderReactorTest is Test, PermitSignature, SettlementEvents, DeployPermit2 {
    using SettlementInfoBuilder for SettlementInfo;
    using CrossChainLimitOrderLib for CrossChainLimitOrder;

    error InvalidSettler();
    error InitiateDeadlinePassed();
    error ValidationFailed();
    error CannotCancelBeforeDeadline(bytes32 orderId);
    error SettlementAlreadyCompleted(bytes32 orderId);
    error CannotFinalizeBeforeDeadline(bytes32 orderId);
    error SettlementDoesNotExist(bytes32 orderId);
    error CanOnlyChallengePendingSettlements(bytes32 orderId);

    uint160 constant ONE = 1 ether;
    string constant LIMIT_ORDER_TYPE_NAME = "CrossChainLimitOrder";

    MockValidationContract validationContract;
    ISettlementOracle settlementOracle;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockERC20 tokenOut2;
    MockERC20 tokenCollateral;
    MockERC20 tokenCollateral2;
    uint256 tokenInAmount;
    uint256 tokenOutAmount;
    uint256 tokenOut2Amount;
    uint256 tokenCollateralAmount;
    uint256 tokenCollateral2Amount;
    uint256 swapperPrivateKey;
    uint256 fillerPrivateKey;
    uint256 challengerPrivateKey;
    address swapper;
    address filler;
    address targetChainFiller;
    address challenger;
    LimitOrderSettler settler;
    CrossChainLimitOrder order;
    address permit2;
    bytes signature;

    function setUp() public {
        // perpare test contracts
        validationContract = new MockValidationContract();
        validationContract.setValid(true);
        settlementOracle = new MockSettlementOracle();
        permit2 = address(deployPermit2());
        settler = new LimitOrderSettler(permit2);

        // prepare swapper/filler address and pk for signing
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        fillerPrivateKey = 0x43214321;
        filler = vm.addr(fillerPrivateKey);
        challengerPrivateKey = 0x56785678;
        challenger = vm.addr(challengerPrivateKey);
        targetChainFiller = address(2);

        // define tokenAmounts
        tokenInAmount = ONE;
        tokenOutAmount = ONE * 2;
        tokenOut2Amount = ONE * 3;
        tokenCollateralAmount = ONE * 4;
        tokenCollateral2Amount = ONE * 5;

        // seed token balances and token approvals
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenCollateral = new MockERC20("Collateral", "CLTRL", 18);
        tokenCollateral2 = new MockERC20("Collateral", "CLTRL", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        tokenOut2 = new MockERC20("Output", "OUT", 18);
        tokenIn.mint(swapper, tokenInAmount);
        tokenCollateral.mint(filler, tokenCollateralAmount);
        tokenCollateral2.mint(challenger, tokenCollateral2Amount);
        tokenOut.mint(filler, tokenOutAmount);
        tokenOut2.mint(filler, tokenOut2Amount);
        tokenIn.forceApprove(swapper, permit2, tokenInAmount);
        tokenCollateral.forceApprove(filler, permit2, tokenCollateralAmount);
        tokenCollateral2.forceApprove(challenger, permit2, tokenCollateral2Amount);
        vm.prank(filler);
        IAllowanceTransfer(permit2).approve(
            address(tokenCollateral), address(settler), uint160(tokenCollateralAmount), uint48(block.timestamp + 1000)
        );

        vm.prank(challenger);
        IAllowanceTransfer(permit2).approve(
            address(tokenCollateral2), address(settler), uint160(tokenCollateral2Amount), uint48(block.timestamp + 1000)
        );

        // setup order
        order.info =
            SettlementInfoBuilder.init(address(settler)).withOfferer(swapper).withOracle(address(settlementOracle));
        order.input = InputToken(address(tokenIn), tokenInAmount, tokenInAmount);
        order.fillerCollateral = CollateralToken(address(tokenCollateral), tokenCollateralAmount);
        order.challengerCollateral = CollateralToken(address(tokenCollateral2), tokenCollateral2Amount);
        order.outputs.push(OutputToken(address(2), address(tokenOut), tokenOutAmount, 69));
        order.outputs.push(OutputToken(address(3), address(tokenOut2), tokenOut2Amount, 70));
        signature = signOrder(swapperPrivateKey, permit2, order);
    }

    function testInitiateSettlementEmitsEventAndCollectsTokens() public {
        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 settlerInputBalanceStart = tokenIn.balanceOf(address(settler));
        uint256 fillerCollateralBalanceStart = tokenCollateral.balanceOf(address(filler));
        uint256 settlerCollateralBalanceStart = tokenCollateral.balanceOf(address(settler));

        vm.expectEmit(true, true, true, true, address(settler));
        emit InitiateSettlement(
            order.hash(),
            swapper,
            filler,
            targetChainFiller,
            address(settlementOracle),
            block.timestamp + 100,
            block.timestamp + 200,
            block.timestamp + 300
            );
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - tokenInAmount);
        assertEq(tokenIn.balanceOf(address(settler)), settlerInputBalanceStart + tokenInAmount);
        assertEq(tokenCollateral.balanceOf(address(filler)), fillerCollateralBalanceStart - tokenCollateralAmount);
        assertEq(tokenCollateral.balanceOf(address(settler)), settlerCollateralBalanceStart + tokenCollateralAmount);
    }

    function testInitiateSettlementStoresTheActiveSettlement() public {
        vm.prank(filler);

        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);
        ActiveSettlement memory settlement = settler.getSettlement(order.hash());

        assertEq(uint8(settlement.status), uint8(SettlementStatus.Pending));
        assertEq(settlement.offerer, swapper);
        assertEq(settlement.originChainFiller, filler);
        assertEq(settlement.targetChainFiller, address(2));
        assertEq(settlement.settlementOracle, address(settlementOracle));
        assertEq(settlement.optimisticDeadline, block.timestamp + order.info.optimisticSettlementPeriod);
        assertEq(settlement.input.token, order.input.token);
        assertEq(settlement.input.amount, order.input.amount);
        assertEq(settlement.fillerCollateral.token, order.fillerCollateral.token);
        assertEq(settlement.fillerCollateral.amount, order.fillerCollateral.amount);
        assertEq(settlement.challengerCollateral.token, order.challengerCollateral.token);
        assertEq(settlement.challengerCollateral.amount, order.challengerCollateral.amount);
        assertEq(settlement.outputs[0].token, order.outputs[0].token);
        assertEq(settlement.outputs[0].amount, order.outputs[0].amount);
        assertEq(settlement.outputs[0].recipient, order.outputs[0].recipient);
        assertEq(settlement.outputs[0].chainId, order.outputs[0].chainId);
        assertEq(settlement.outputs[1].token, order.outputs[1].token);
        assertEq(settlement.outputs[1].amount, order.outputs[1].amount);
        assertEq(settlement.outputs[1].recipient, order.outputs[1].recipient);
        assertEq(settlement.outputs[1].chainId, order.outputs[1].chainId);
    }

    function testInitiateSettlementRevertsOnInvalidSettlerContract() public {
        order.info.settlerContract = address(1);
        signature = signOrder(swapperPrivateKey, permit2, order);

        vm.expectRevert(InvalidSettler.selector);
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);
    }

    function testInitiateSettlementRevertsWhenDeadlinePassed() public {
        vm.warp(block.timestamp + 101);
        vm.expectRevert(InitiateDeadlinePassed.selector);
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);
    }

    function testInitiateSettlementRevertsWhenCustomValidationFails() public {
        order.info.validationContract = address(validationContract);
        signature = signOrder(swapperPrivateKey, permit2, order);

        validationContract.setValid(false);

        vm.expectRevert(ValidationFailed.selector);
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);
    }

    function testChallengeCollectsBondAndUpdatesStatus() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);

        uint256 challengerCollateralBalanceStart = tokenCollateral2.balanceOf(address(challenger));
        uint256 settlerCollateralBalanceStart = tokenCollateral2.balanceOf(address(settler));

        vm.prank(challenger);
        settler.challengeSettlement(order.hash());

        assertEq(tokenCollateral2.balanceOf(address(challenger)), challengerCollateralBalanceStart - tokenCollateral2Amount);
        assertEq(tokenCollateral2.balanceOf(address(settler)), settlerCollateralBalanceStart + tokenCollateral2Amount);
    }

    function testChallengeUpdatesSettlementStatusAndEmitsEvent() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);

        vm.expectEmit(true, true, true, true, address(settler));
        emit SettlementChallenged(order.hash(), challenger);
        vm.prank(challenger);
        settler.challengeSettlement(order.hash());

        uint8 newStatus = uint8(settler.getSettlement(order.hash()).status);

        assertEq(newStatus, uint8(SettlementStatus.Challenged));
    }

    function testChallengeRevertsIfSettlementDoesNotExist() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);

        vm.expectRevert(abi.encodePacked(SettlementDoesNotExist.selector, keccak256("0x69")));
        vm.prank(challenger);
        settler.challengeSettlement(keccak256("0x69"));
    }

    function testChallengeRevertsIfItIsAlreadyChallenged() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);

        vm.prank(challenger);
        settler.challengeSettlement(order.hash());
        vm.expectRevert(abi.encodePacked(CanOnlyChallengePendingSettlements.selector, order.hash()));
        vm.prank(challenger);
        settler.challengeSettlement(order.hash());
    }

    function testCancelSettlementSuccessfullyReturnsInputandCollateral() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);
        vm.warp(settler.getSettlement(order.hash()).challengeDeadline + 1);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 settlerInputBalanceStart = tokenIn.balanceOf(address(settler));
        uint256 swapperCollateralBalanceStart = tokenCollateral.balanceOf(address(swapper));
        uint256 settlerCollateralBalanceStart = tokenCollateral.balanceOf(address(settler));

        settler.cancelSettlement(order.hash());

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart + ONE);
        assertEq(tokenIn.balanceOf(address(settler)), settlerInputBalanceStart - ONE);
        assertEq(tokenCollateral.balanceOf(address(swapper)), swapperCollateralBalanceStart + ONE);
        assertEq(tokenCollateral.balanceOf(address(settler)), settlerCollateralBalanceStart - ONE);
    }

    function testCancelSettlementUpdatesSettlementStatus() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);
        vm.warp(settler.getSettlement(order.hash()).challengeDeadline + 1);

        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStatus.Pending));
        settler.cancelSettlement(order.hash());
        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStatus.Cancelled));
    }

    function testCancelSettlementRevertsBeforeDeadline() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);

        vm.expectRevert(abi.encodePacked(CannotCancelBeforeDeadline.selector, order.hash()));
        settler.cancelSettlement(order.hash());
    }

    function testCancelSettlementRevertsIfAlreadyCancelled() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);

        vm.warp(settler.getSettlement(order.hash()).challengeDeadline + 1);
        settler.cancelSettlement(order.hash());
        vm.expectRevert(abi.encodePacked(SettlementAlreadyCompleted.selector, order.hash()));
        settler.cancelSettlement(order.hash());
    }

    function testFinalizeOptimisticallySuccessfullyTransfersInputAndCollateral() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), address(1));

        uint256 fillerInputBalanceStart = tokenIn.balanceOf(address(filler));
        uint256 settlerInputBalanceStart = tokenIn.balanceOf(address(settler));
        uint256 fillerCollateralBalanceStart = tokenCollateral.balanceOf(address(filler));
        uint256 settlerCollateralBalanceStart = tokenCollateral.balanceOf(address(settler));

        vm.warp(settler.getSettlement(order.hash()).optimisticDeadline + 1);
        settler.finalizeSettlement(order.hash());

        assertEq(tokenIn.balanceOf(address(filler)), fillerInputBalanceStart + tokenInAmount);
        assertEq(tokenIn.balanceOf(address(settler)), settlerInputBalanceStart - tokenInAmount);
        assertEq(tokenCollateral.balanceOf(address(filler)), fillerCollateralBalanceStart + tokenCollateralAmount);
        assertEq(tokenCollateral.balanceOf(address(settler)), settlerCollateralBalanceStart - tokenCollateralAmount);
    }

    function testFinalizeOptimisticallyUpdatesSettlementStatus() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);
        vm.warp(settler.getSettlement(order.hash()).challengeDeadline + 1);

        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStatus.Pending));
        vm.warp(settler.getSettlement(order.hash()).optimisticDeadline + 1);
        settler.finalizeSettlement(order.hash());
        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStatus.Success));
    }

    function testFinalizeRevertsIfAlreadyFinalized() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);

        vm.warp(settler.getSettlement(order.hash()).optimisticDeadline + 1);
        settler.finalizeSettlement(order.hash());

        vm.expectRevert(abi.encodePacked(SettlementAlreadyCompleted.selector, order.hash()));
        settler.finalizeSettlement(order.hash());
    }

    function testFinalizeRevertsIfOptimisticDeadlineHasNotPassed() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);

        vm.expectRevert(abi.encodePacked(CannotFinalizeBeforeDeadline.selector, order.hash()));
        settler.finalizeSettlement(order.hash());
    }

    function testFinalizeChallengedOrderSuccessfullyReturnsFunds() public {
        vm.prank(filler);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), targetChainFiller);

        vm.prank(challenger);
        settler.challengeSettlement(order.hash());

        settlementOracle.logSettlementInfo(order.hash(), targetChainFiller, order.outputs);

        uint256 fillerInputBalanceStart = tokenIn.balanceOf(address(filler));
        uint256 fillerCollateralBalanceStart = tokenCollateral.balanceOf(address(filler));
        uint256 fillerCollateral2BalanceStart = tokenCollateral2.balanceOf(address(filler));
        uint256 settlerInputBalanceStart = tokenIn.balanceOf(address(settler));
        uint256 settlerCollateralBalanceStart = tokenCollateral.balanceOf(address(settler));
        uint256 settlerCollateral2BalanceStart = tokenCollateral2.balanceOf(address(settler));

        settler.finalizeSettlement(order.hash());

        assertEq(tokenIn.balanceOf(address(filler)), fillerInputBalanceStart + tokenInAmount);
        assertEq(tokenIn.balanceOf(address(settler)), settlerInputBalanceStart - tokenInAmount);
        assertEq(tokenCollateral.balanceOf(address(filler)), fillerCollateralBalanceStart + tokenCollateralAmount);
        assertEq(tokenCollateral.balanceOf(address(settler)), settlerCollateralBalanceStart - tokenCollateralAmount);
        assertEq(tokenCollateral2.balanceOf(address(filler)), fillerCollateral2BalanceStart + tokenCollateral2Amount);
        assertEq(tokenCollateral2.balanceOf(address(settler)), settlerCollateral2BalanceStart - tokenCollateral2Amount);
    }
}

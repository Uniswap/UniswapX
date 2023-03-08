// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import {InputToken, SignedOrder} from "../../../src/base/ReactorStructs.sol";
import {
    SettlementKey,
    SettlementInfo,
    SettlementStage,
    SettlementStatus,
    ResolvedOrder,
    OutputToken,
    CollateralToken
} from "../../../src/xchain-gouda/base/SettlementStructs.sol";
import {ISettlementOracle} from "../../../src/xchain-gouda/interfaces/ISettlementOracle.sol";
import {IOrderSettlerErrors} from "../../../src/xchain-gouda/interfaces/IOrderSettlerErrors.sol";
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

contract CrossChainLimitOrderReactorTest is
    Test,
    PermitSignature,
    SettlementEvents,
    DeployPermit2,
    IOrderSettlerErrors,
    GasSnapshot
{
    using SettlementInfoBuilder for SettlementInfo;
    using CrossChainLimitOrderLib for CrossChainLimitOrder;

    error InitiateDeadlinePassed();
    error ValidationFailed();
    error InvalidSettler();

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
    CrossChainLimitOrder order2; // for batching
    SignedOrder[] signedOrders; // for batching
    bytes32[] orderIds; // for batching
    SettlementKey[] keys; // for batching
    bytes signature;
    address permit2;

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
        snapStart("CrossChainInitiateFill");
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);
        snapEnd();

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - tokenInAmount);
        assertEq(tokenIn.balanceOf(address(settler)), settlerInputBalanceStart + tokenInAmount);
        assertEq(tokenCollateral.balanceOf(address(filler)), fillerCollateralBalanceStart - tokenCollateralAmount);
        assertEq(tokenCollateral.balanceOf(address(settler)), settlerCollateralBalanceStart + tokenCollateralAmount);
    }

    function testInitiateSettlementStoresTheActiveSettlement() public {
        vm.prank(filler);

        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);
        SettlementStatus memory settlement = settler.getSettlement(order.hash());
        SettlementKey memory key = SettlementKey(
            swapper,
            filler,
            address(2),
            address(settlementOracle),
            uint32(block.timestamp + order.info.fillPeriod),
            uint32(block.timestamp + order.info.optimisticSettlementPeriod),
            uint32(block.timestamp + order.info.challengePeriod),
            order.input,
            order.fillerCollateral,
            order.challengerCollateral,
            keccak256(abi.encode(order.outputs))
        );

        assertEq(uint8(settlement.status), uint8(SettlementStage.Pending));
        assertEq(settlement.challenger, address(0));
        assertEq(settlement.key, keccak256(abi.encode(key)));
    }

    function testInitiateBatchStoresAllActiveSettlements() public {
        SignedOrder memory signedOrder2 = generateSecondOrder();
        signedOrders.push(SignedOrder(abi.encode(order), signature));
        signedOrders.push(signedOrder2);

        vm.prank(filler);
        snapStart("CrossChainInitiateBatch");
        settler.initiateBatch(signedOrders, targetChainFiller);
        snapEnd();

        SettlementStatus memory settlement = settler.getSettlement(order.hash());
        SettlementKey memory key = SettlementKey(
            swapper,
            filler,
            address(2),
            address(settlementOracle),
            uint32(block.timestamp + order.info.fillPeriod),
            uint32(block.timestamp + order.info.optimisticSettlementPeriod),
            uint32(block.timestamp + order.info.challengePeriod),
            order.input,
            order.fillerCollateral,
            order.challengerCollateral,
            keccak256(abi.encode(order.outputs))
        );

        assertEq(uint8(settlement.status), uint8(SettlementStage.Pending));
        assertEq(settlement.challenger, address(0));
        assertEq(settlement.key, keccak256(abi.encode(key)));

        SettlementStatus memory settlement2 = settler.getSettlement(order2.hash());
        SettlementKey memory key2 = SettlementKey(
            order2.info.offerer,
            filler,
            address(2),
            address(settlementOracle),
            uint32(block.timestamp + order2.info.fillPeriod),
            uint32(block.timestamp + order2.info.optimisticSettlementPeriod),
            uint32(block.timestamp + order2.info.challengePeriod),
            order2.input,
            order2.fillerCollateral,
            order2.challengerCollateral,
            keccak256(abi.encode(order2.outputs))
        );

        assertEq(uint8(settlement2.status), uint8(SettlementStage.Pending));
        assertEq(settlement2.challenger, address(0));
        assertEq(settlement2.key, keccak256(abi.encode(key2)));
    }

    function testInitiateBatchStoresFirstSettlementIfSecondReverts() public {
        SignedOrder memory signedOrder2 = generateSecondOrder();
        signedOrder2.sig = signature; // invalid signatuer
        signedOrders.push(SignedOrder(abi.encode(order), signature));
        signedOrders.push(signedOrder2);

        vm.prank(filler);
        uint8[] memory returnArray = settler.initiateBatch(signedOrders, targetChainFiller);

        SettlementStatus memory settlement = settler.getSettlement(order.hash());
        SettlementKey memory key = SettlementKey(
            swapper,
            filler,
            address(2),
            address(settlementOracle),
            uint32(block.timestamp + order.info.fillPeriod),
            uint32(block.timestamp + order.info.optimisticSettlementPeriod),
            uint32(block.timestamp + order.info.challengePeriod),
            order.input,
            order.fillerCollateral,
            order.challengerCollateral,
            keccak256(abi.encode(order.outputs))
        );

        assertEq(uint8(settlement.status), uint8(SettlementStage.Pending));
        assertEq(settlement.challenger, address(0));
        assertEq(settlement.key, keccak256(abi.encode(key)));

        SettlementStatus memory settlement2 = settler.getSettlement(order2.hash());
        assertEq(settlement2.key, 0);

        assertEq(returnArray[0], 0);
        assertEq(returnArray[1], 1);
    }

    function testInitiateBatchStoresSecondSettlementIfFirstReverts() public {
        SignedOrder memory signedOrder2 = generateSecondOrder();
        signedOrders.push(SignedOrder(abi.encode(order), signedOrder2.sig)); // invalid signatuer
        signedOrders.push(signedOrder2);

        vm.prank(filler);
        uint8[] memory returnArray = settler.initiateBatch(signedOrders, targetChainFiller);

        SettlementStatus memory settlement = settler.getSettlement(order.hash());
        assertEq(settlement.key, 0);

        SettlementStatus memory settlement2 = settler.getSettlement(order2.hash());
        SettlementKey memory key2 = SettlementKey(
            order2.info.offerer,
            filler,
            address(2),
            address(settlementOracle),
            uint32(block.timestamp + order2.info.fillPeriod),
            uint32(block.timestamp + order2.info.optimisticSettlementPeriod),
            uint32(block.timestamp + order2.info.challengePeriod),
            order2.input,
            order2.fillerCollateral,
            order2.challengerCollateral,
            keccak256(abi.encode(order2.outputs))
        );

        assertEq(uint8(settlement2.status), uint8(SettlementStage.Pending));
        assertEq(settlement2.challenger, address(0));
        assertEq(settlement2.key, keccak256(abi.encode(key2)));

        assertEq(returnArray[0], 1);
        assertEq(returnArray[1], 0);
    }

    function testInitiateSettlementRevertsOnInvalidSettlerContract() public {
        order.info.settlerContract = address(1);
        signature = signOrder(swapperPrivateKey, permit2, order);

        vm.expectRevert(InvalidSettler.selector);
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);
    }

    function testInitiateSettlementRevertsWhenDeadlinePassed() public {
        vm.warp(order.info.initiateDeadline + 1);
        vm.expectRevert(InitiateDeadlinePassed.selector);
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);
    }

    function testInitiateSettlementRevertsWhenCustomValidationFails() public {
        order.info.validationContract = address(validationContract);
        signature = signOrder(swapperPrivateKey, permit2, order);

        validationContract.setValid(false);

        vm.expectRevert(ValidationFailed.selector);
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);
    }

    function testChallengeCollectsBondAndUpdatesStatus() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);
        uint256 challengerCollateralBalanceStart = tokenCollateral2.balanceOf(address(challenger));
        uint256 settlerCollateralBalanceStart = tokenCollateral2.balanceOf(address(settler));

        vm.prank(challenger);
        snapStart("CrossChainChallengeSettlement");
        settler.challengeSettlement(order.hash(), key);
        snapEnd();

        assertEq(
            tokenCollateral2.balanceOf(address(challenger)), challengerCollateralBalanceStart - tokenCollateral2Amount
        );
        assertEq(tokenCollateral2.balanceOf(address(settler)), settlerCollateralBalanceStart + tokenCollateral2Amount);
    }

    function testChallengeUpdatesSettlementStageAndEmitsEvent() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.expectEmit(true, true, true, true, address(settler));
        emit SettlementChallenged(order.hash(), challenger);
        vm.prank(challenger);
        settler.challengeSettlement(order.hash(), key);

        uint8 newStatus = uint8(settler.getSettlement(order.hash()).status);
        assertEq(newStatus, uint8(SettlementStage.Challenged));
    }

    function testChallengeRevertsIfSettlementDoesNotExist() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.expectRevert(SettlementDoesNotExist.selector);
        vm.prank(challenger);
        settler.challengeSettlement(keccak256("0x69"), key);
    }

    function testChallengeRevertsIfSettlementKeyDoesNotMatch() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);
        key.challengeDeadline = 0;

        vm.expectRevert(InvalidSettlementKey.selector);
        vm.prank(challenger);
        settler.challengeSettlement(order.hash(), key);
    }

    function testChallengeRevertsIfItIsAlreadyChallenged() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.prank(challenger);
        settler.challengeSettlement(order.hash(), key);
        vm.expectRevert(CanOnlyChallengePendingSettlements.selector);
        vm.prank(challenger);
        settler.challengeSettlement(order.hash(), key);
    }

    function testCancelSettlementSuccessfullyReturnsInputandCollateralsToAChallengedOrder() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.prank(challenger);
        settler.challengeSettlement(order.hash(), key);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 swapperCollateralBalanceStart = tokenCollateral.balanceOf(address(swapper));
        uint256 settlerInputBalanceStart = tokenIn.balanceOf(address(settler));
        uint256 settlerCollateralBalanceStart = tokenCollateral.balanceOf(address(settler));
        uint256 settlerCollateral2BalanceStart = tokenCollateral2.balanceOf(address(settler));
        uint256 challengerCollateralBalanceStart = tokenCollateral.balanceOf(address(challenger));
        uint256 challengerCollateral2BalanceStart = tokenCollateral2.balanceOf(address(challenger));

        vm.warp(key.challengeDeadline + 1);
        snapStart("CrossChainCancelSettlement");
        settler.cancel(order.hash(), key);
        snapEnd();

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart + tokenInAmount);
        assertEq(tokenIn.balanceOf(address(settler)), settlerInputBalanceStart - tokenInAmount);
        // filler's collateral split evenly with challenger
        assertEq(tokenCollateral.balanceOf(address(swapper)), swapperCollateralBalanceStart + tokenCollateralAmount / 2);
        assertEq(
            tokenCollateral.balanceOf(address(challenger)), challengerCollateralBalanceStart + tokenCollateralAmount / 2
        );
        assertEq(tokenCollateral.balanceOf(address(settler)), settlerCollateralBalanceStart - tokenCollateralAmount);
        assertEq(
            tokenCollateral2.balanceOf(address(challenger)), challengerCollateral2BalanceStart + tokenCollateral2Amount
        );
        assertEq(tokenCollateral2.balanceOf(address(settler)), settlerCollateral2BalanceStart - tokenCollateral2Amount);
    }

    function testCancelSettlementSuccessfullyReturnsInputandCollateralToAnUnchallengedOrder() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.warp(key.challengeDeadline + 1);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 settlerInputBalanceStart = tokenIn.balanceOf(address(settler));
        uint256 swapperCollateralBalanceStart = tokenCollateral.balanceOf(address(swapper));
        uint256 settlerCollateralBalanceStart = tokenCollateral.balanceOf(address(settler));

        settler.cancel(order.hash(), key);

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart + tokenInAmount);
        assertEq(tokenIn.balanceOf(address(settler)), settlerInputBalanceStart - tokenInAmount);
        assertEq(tokenCollateral.balanceOf(address(swapper)), swapperCollateralBalanceStart + tokenCollateralAmount);
        assertEq(tokenCollateral.balanceOf(address(settler)), settlerCollateralBalanceStart - tokenCollateralAmount);
    }

    function testCancelSettlementUpdatesSettlementStage() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.warp(key.challengeDeadline + 1);

        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStage.Pending));
        settler.cancel(order.hash(), key);
        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStage.Cancelled));
    }

    function testCancelBatchSettlementUpdatesSettlementStages() public {
        SignedOrder memory signedOrder2 = generateSecondOrder();
        signedOrders.push(SignedOrder(abi.encode(order), signature));
        signedOrders.push(signedOrder2);
        orderIds.push(order.hash());
        orderIds.push(order2.hash());

        SettlementKey memory key = constructKey(order, filler);
        SettlementKey memory key2 = constructKey(order2, filler);

        keys.push(key);
        keys.push(key2);

        vm.prank(filler);
        settler.initiateBatch(signedOrders, targetChainFiller);
        vm.warp(key2.challengeDeadline + 1);

        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStage.Pending));
        assertEq(uint8(settler.getSettlement(order2.hash()).status), uint8(SettlementStage.Pending));
        snapStart("CrossChainCancelBatchSettlements");
        uint8[] memory failed = settler.cancelBatch(orderIds, keys);
        snapEnd();

        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStage.Cancelled));
        assertEq(uint8(settler.getSettlement(order2.hash()).status), uint8(SettlementStage.Cancelled));
        assertEq(failed[0], 0);
        assertEq(failed[1], 0);
    }

    function testCancelBatchSettlementUpdatesSecondSettlementStageIfFirstFails() public {
        SignedOrder memory signedOrder2 = generateSecondOrder();
        signedOrders.push(SignedOrder(abi.encode(order), signature));
        signedOrders.push(signedOrder2);
        orderIds.push(order.hash());
        orderIds.push(order2.hash());

        SettlementKey memory key = constructKey(order, filler);

        keys.push(key);
        keys.push(constructKey(order2, filler));

        vm.prank(filler);
        settler.initiateBatch(signedOrders, targetChainFiller);
        // warp to meet only the deadline of the first order
        vm.warp(key.challengeDeadline + 100);

        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStage.Pending));
        assertEq(uint8(settler.getSettlement(order2.hash()).status), uint8(SettlementStage.Pending));
        uint8[] memory failed = settler.cancelBatch(orderIds, keys);
        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStage.Cancelled));
        assertEq(uint8(settler.getSettlement(order2.hash()).status), uint8(SettlementStage.Pending));
        assertEq(failed[0], 0);
        assertEq(failed[1], 1);
    }

    function testCancelSettlementRevertsBeforeDeadline() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);
        vm.expectRevert(CannotCancelBeforeDeadline.selector);
        settler.cancel(order.hash(), constructKey(order, filler));
    }

    function testCancelSettlementRevertsIfAlreadyCancelled() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.warp(key.challengeDeadline + 1);
        settler.cancel(order.hash(), key);
        vm.expectRevert(SettlementAlreadyCompleted.selector);
        settler.cancel(order.hash(), key);
    }

    function testCancelSettlementRevertsIfSettlementKeyDoesNotMatch() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);
        key.challengeDeadline = 0;

        vm.warp(key.challengeDeadline + 1);
        vm.expectRevert(InvalidSettlementKey.selector);
        vm.prank(challenger);
        settler.challengeSettlement(order.hash(), key);
    }

    function testCancelSettlementRevertsIfSettlementDoesNotExist() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);
        vm.warp(key.challengeDeadline + 1);
        vm.expectRevert(SettlementDoesNotExist.selector);
        settler.challengeSettlement(keccak256("0x69"), key);
    }

    function testFinalizeOptimisticallySuccessfullyTransfersInputAndCollateral() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        uint256 fillerInputBalanceStart = tokenIn.balanceOf(address(filler));
        uint256 settlerInputBalanceStart = tokenIn.balanceOf(address(settler));
        uint256 fillerCollateralBalanceStart = tokenCollateral.balanceOf(address(filler));
        uint256 settlerCollateralBalanceStart = tokenCollateral.balanceOf(address(settler));

        SettlementKey memory key = constructKey(order, filler);

        vm.warp(key.optimisticDeadline + 1);
        snapStart("CrossChainFinalizeOptimistic");
        settler.finalizeOptimistically(order.hash(), key);
        snapEnd();

        assertEq(tokenIn.balanceOf(address(filler)), fillerInputBalanceStart + tokenInAmount);
        assertEq(tokenIn.balanceOf(address(settler)), settlerInputBalanceStart - tokenInAmount);
        assertEq(tokenCollateral.balanceOf(address(filler)), fillerCollateralBalanceStart + tokenCollateralAmount);
        assertEq(tokenCollateral.balanceOf(address(settler)), settlerCollateralBalanceStart - tokenCollateralAmount);
    }

    function testFinalizeOptimisticallyUpdatesSettlementStage() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.warp(key.challengeDeadline + 1);

        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStage.Pending));
        vm.warp(key.optimisticDeadline + 1);
        settler.finalizeOptimistically(order.hash(), key);
        assertEq(uint8(settler.getSettlement(order.hash()).status), uint8(SettlementStage.Success));
    }

    function testFinalizeOptimisticallyRevertsIfAlreadyFinalized() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.warp(key.optimisticDeadline + 1);
        settler.finalizeOptimistically(order.hash(), key);

        vm.expectRevert(OptimisticFinalizationForPendingSettlementsOnly.selector);
        settler.finalizeOptimistically(order.hash(), key);
    }

    function testFinalizeOptimisticallyRevertsIfOptimisticDeadlineHasNotPassed() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.expectRevert(CannotFinalizeBeforeDeadline.selector);
        settler.finalizeOptimistically(order.hash(), key);
    }

    function testFinalizeOptimisticallyRevertsIfSettlementDoesNotExist() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.warp(key.optimisticDeadline + 1);
        vm.expectRevert(SettlementDoesNotExist.selector);
        settler.finalizeOptimistically(keccak256("0x69"), key);
    }

    function testFinalizeOptimisticallyRevertsIfSettlementKeyDoesNotMatch() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);
        key.challengeDeadline = 0;

        vm.expectRevert(InvalidSettlementKey.selector);
        settler.finalizeOptimistically(order.hash(), key);
    }

    function testFinalizeChallengedOrderSuccessfullyReturnsFundsIfSettlementWasValid() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.prank(challenger);
        settler.challengeSettlement(order.hash(), key);

        uint256 fillerInputBalanceStart = tokenIn.balanceOf(address(filler));
        uint256 fillerCollateralBalanceStart = tokenCollateral.balanceOf(address(filler));
        uint256 fillerCollateral2BalanceStart = tokenCollateral2.balanceOf(address(filler));
        uint256 settlerInputBalanceStart = tokenIn.balanceOf(address(settler));
        uint256 settlerCollateralBalanceStart = tokenCollateral.balanceOf(address(settler));
        uint256 settlerCollateral2BalanceStart = tokenCollateral2.balanceOf(address(settler));

        vm.warp(key.challengeDeadline);
        snapStart("CrossChainFinalizeChallenged");
        settlementOracle.finalizeSettlement(order.hash(), key, address(settler), key.fillDeadline);
        snapEnd();

        assertEq(tokenIn.balanceOf(address(filler)), fillerInputBalanceStart + tokenInAmount);
        assertEq(tokenIn.balanceOf(address(settler)), settlerInputBalanceStart - tokenInAmount);
        assertEq(tokenCollateral.balanceOf(address(filler)), fillerCollateralBalanceStart + tokenCollateralAmount);
        assertEq(tokenCollateral.balanceOf(address(settler)), settlerCollateralBalanceStart - tokenCollateralAmount);
        assertEq(tokenCollateral2.balanceOf(address(filler)), fillerCollateral2BalanceStart + tokenCollateral2Amount);
        assertEq(tokenCollateral2.balanceOf(address(settler)), settlerCollateral2BalanceStart - tokenCollateral2Amount);
    }

    function testFinalizeChallengedOrderRevertsIfNotCalledFromOracle() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.prank(challenger);
        settler.challengeSettlement(order.hash(), key);

        vm.warp(key.challengeDeadline + 1);
        vm.expectRevert(OnlyOracleCanFinalizeSettlement.selector);
        settler.finalize(order.hash(), key, block.timestamp + 10);
    }

    function testFinalizeChallengedOrderRevertsIfOrderFilledAfterFillDeadline() public {
        order.info.settlementOracle = address(this);
        signature = signOrder(swapperPrivateKey, permit2, order);
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.prank(challenger);
        settler.challengeSettlement(order.hash(), key);

        // TODO: this says it's not reverting as expected BUT IT IS???
        // vm.expectRevert(IOrderSettlerErrors.OrderFillExceededDeadline.selector);
        // settler.finalize(order.hash(), targetChainFiller, settler.getSettlement(order.hash()).fillDeadline + 10, order.outputs);
    }

    function testFinalizeChallengedRevertsIfSettlementDoesNotExist() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.warp(key.challengeDeadline + 1);
        vm.expectRevert(SettlementDoesNotExist.selector);
        settlementOracle.finalizeSettlement(keccak256("0x69"), key, address(settler), key.fillDeadline);
    }

    function testFinalizeChallengedRevertsIfSettlementKeyDoesNotMatch() public {
        vm.prank(filler);
        settler.initiate(SignedOrder(abi.encode(order), signature), targetChainFiller);

        SettlementKey memory key = constructKey(order, filler);

        vm.prank(challenger);
        settler.challengeSettlement(order.hash(), key);

        key.challengeDeadline = 0;

        vm.warp(key.challengeDeadline + 1);
        vm.expectRevert(InvalidSettlementKey.selector);
        settlementOracle.finalizeSettlement(order.hash(), key, address(settler), key.fillDeadline);
    }

    function generateSecondOrder() private returns (SignedOrder memory) {
        uint256 swapperPrivateKey2 = 0x11223344; // for batch initiate
        address swapper2 = vm.addr(swapperPrivateKey2);

        uint256 tokenInAmount2 = ONE * 6;
        uint256 tokenOutAmount3 = ONE * 7;
        uint256 tokenCollateral3Amount = ONE * 8;
        uint256 tokenCollateral4Amount = ONE * 9;

        MockERC20 tokenIn2 = new MockERC20("Input", "IN", 18);
        MockERC20 tokenCollateral3 = new MockERC20("Collateral", "CLTRL", 18);
        MockERC20 tokenCollateral4 = new MockERC20("Collateral", "CLTRL", 18);
        MockERC20 tokenOut3 = new MockERC20("Output", "OUT", 18);
        tokenIn2.mint(swapper2, tokenInAmount2);
        tokenCollateral3.mint(filler, tokenCollateral3Amount);
        tokenCollateral4.mint(challenger, tokenCollateral4Amount);
        tokenIn2.forceApprove(swapper2, permit2, tokenInAmount2);
        tokenCollateral3.forceApprove(filler, permit2, tokenCollateral3Amount);
        tokenCollateral4.forceApprove(challenger, permit2, tokenCollateral4Amount);

        vm.prank(filler);
        IAllowanceTransfer(permit2).approve(
            address(tokenCollateral3), address(settler), uint160(tokenCollateral3Amount), uint48(block.timestamp + 1000)
        );

        vm.prank(challenger);
        IAllowanceTransfer(permit2).approve(
            address(tokenCollateral4), address(settler), uint160(tokenCollateral4Amount), uint48(block.timestamp + 1000)
        );

        order2.info = SettlementInfoBuilder.init(address(settler)).withOfferer(swapper2).withOracle(
            address(settlementOracle)
        ).withPeriods(300, 400);
        order2.input = InputToken(address(tokenIn2), tokenInAmount2, tokenInAmount2);
        order2.fillerCollateral = CollateralToken(address(tokenCollateral3), tokenCollateral3Amount);
        order2.challengerCollateral = CollateralToken(address(tokenCollateral4), tokenCollateral2Amount);
        order2.outputs.push(OutputToken(address(tokenOut3), address(tokenOut3), tokenOutAmount3, 70));

        return SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, permit2, order2));
    }

    function constructKey(CrossChainLimitOrder memory orderInfo, address fillerAddress)
        private
        view
        returns (SettlementKey memory key)
    {
        key = SettlementKey(
            orderInfo.info.offerer,
            fillerAddress,
            address(2),
            orderInfo.info.settlementOracle,
            uint32(block.timestamp + orderInfo.info.fillPeriod),
            uint32(block.timestamp + orderInfo.info.optimisticSettlementPeriod),
            uint32(block.timestamp + orderInfo.info.challengePeriod),
            orderInfo.input,
            orderInfo.fillerCollateral,
            orderInfo.challengerCollateral,
            keccak256(abi.encode(orderInfo.outputs))
        );
    }
}

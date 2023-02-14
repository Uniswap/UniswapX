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

    uint160 constant ONE = 1 ether;
    string constant LIMIT_ORDER_TYPE_NAME = "CrossChainLimitOrder";

    MockValidationContract validationContract;
    ISettlementOracle settlementOracle;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockERC20 tokenOut2;
    MockERC20 tokenCollateral;
    uint256 makerPrivateKey;
    uint256 takerPrivateKey;
    address maker;
    address taker;
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

        // prepare maker/taker address and pk for signing
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        takerPrivateKey = 0x43214321;
        taker = vm.addr(takerPrivateKey);

        // seed token balances and token approvals
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenCollateral = new MockERC20("Collateral", "CLTRL", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        tokenOut2 = new MockERC20("Output", "OUT", 18);
        tokenIn.mint(maker, ONE);
        tokenCollateral.mint(taker, ONE);
        tokenOut.mint(taker, ONE);
        tokenOut2.mint(taker, ONE);
        tokenIn.forceApprove(maker, permit2, ONE);
        tokenCollateral.forceApprove(taker, permit2, ONE);
        vm.prank(taker);
        IAllowanceTransfer(permit2).approve(
            address(tokenCollateral), address(settler), ONE, uint48(block.timestamp + 1000)
        );

        // setup order
        order.info =
            SettlementInfoBuilder.init(address(settler)).withOfferer(maker).withOracle(address(settlementOracle));
        order.input = InputToken(address(tokenIn), ONE, ONE);
        order.collateral = CollateralToken(address(tokenCollateral), ONE);
        order.outputs.push(OutputToken(address(2), address(tokenOut), 100, 69));
        order.outputs.push(OutputToken(address(3), address(tokenOut2), 200, 70));
        signature = signOrder(makerPrivateKey, permit2, order);
    }

    function testInitiateSettlementEmitsEventAndCollectsTokens() public {
        uint256 makerInputBalanceStart = tokenIn.balanceOf(address(maker));
        uint256 settlerInputBalanceStart = tokenIn.balanceOf(address(settler));
        uint256 takerCollateralBalanceStart = tokenCollateral.balanceOf(address(taker));
        uint256 settlerCollateralBalanceStart = tokenCollateral.balanceOf(address(settler));

        vm.expectEmit(true, true, true, true, address(settler));
        emit InitiateSettlement(
            order.hash(), maker, taker, address(1), address(settlementOracle), block.timestamp + 100
            );

        vm.prank(taker);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), address(1));

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - ONE);
        assertEq(tokenIn.balanceOf(address(settler)), settlerInputBalanceStart + ONE);
        assertEq(tokenCollateral.balanceOf(address(taker)), takerCollateralBalanceStart - ONE);
        assertEq(tokenCollateral.balanceOf(address(settler)), settlerCollateralBalanceStart + ONE);
    }

    function testInitiateSettlementStoresTheActiveSettlement() public {
        vm.prank(taker);

        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), address(2));
        ActiveSettlement memory settlement = settler.getSettlement(order.hash());

        assertEq(uint8(settlement.status), uint8(SettlementStatus.Pending));
        assertEq(settlement.offerer, maker);
        assertEq(settlement.originChainFiller, taker);
        assertEq(settlement.targetChainFiller, address(2));
        assertEq(settlement.settlementOracle, address(settlementOracle));
        assertEq(settlement.deadline, block.timestamp + order.info.settlementPeriod);
        assertEq(settlement.input.token, order.input.token);
        assertEq(settlement.input.amount, order.input.amount);
        assertEq(settlement.collateral.token, order.collateral.token);
        assertEq(settlement.collateral.amount, order.collateral.amount);
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
        signature = signOrder(makerPrivateKey, permit2, order);

        vm.expectRevert(InvalidSettler.selector);
        vm.prank(taker);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), address(2));
    }

    function testInitiateSettlementRevertsWhenDeadlinePassed() public {
        vm.warp(block.timestamp + 101);
        vm.expectRevert(InitiateDeadlinePassed.selector);
        vm.prank(taker);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), address(2));
    }

    function testInitiateSettlementRevertsWhenCustomValidationFails() public {
        order.info.validationContract = address(validationContract);
        signature = signOrder(makerPrivateKey, permit2, order);

        validationContract.setValid(false);

        vm.expectRevert(ValidationFailed.selector);
        vm.prank(taker);
        settler.initiateSettlement(SignedOrder(abi.encode(order), signature), address(2));
    }
}

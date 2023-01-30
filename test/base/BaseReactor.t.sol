// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {Test} from "forge-std/Test.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {OrderInfo, InputToken, OutputToken} from '../../src/base/ReactorStructs.sol';
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";

abstract contract BaseReactorTest is GasSnapshot, ReactorEvents, Test {
    using OrderInfoBuilder for OrderInfo;
    uint256 constant ONE = 10 ** 18;

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockFillContract fillContract;
    ISignatureTransfer permit2;
    BaseReactor reactor;
    uint256 makerPrivateKey;
    address maker;

    error InvalidNonce();
    error InvalidSigner();

    function name() virtual public returns (string memory) {}
    
    /// @dev 
    function setUp() virtual public {}

    function createReactor() virtual public returns (BaseReactor) {}

    /// @dev returns (order, signature, orderHash, OrderInfo)
    // function createAndSignOrder() virtual public returns (SignedOrder, bytes32 orderHash, OrderInfo memory orderInfo) {}
    function createAndSignOrder(OrderInfo memory _info, uint256 inputAmount, uint256 outputAmount) virtual public returns (SignedOrder memory signedOrder, bytes32 orderHash) {}

    function createAndSignBatchOrders(OrderInfo[] memory _infos, uint256[] memory inputAmounts, uint256[][] memory outputAmounts) virtual public returns (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) {}

    /// @dev Basic execute test, checks balance before and after
    function testBaseExecute() public {
        // Seed both maker and fillContract with enough tokens (important for dutch order)
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(maker), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        tokenIn.forceApprove(maker, address(permit2), inputAmount);

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100);
        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(
            orderInfo,
            inputAmount, 
            outputAmount
        );

        uint256 makerInputBalanceStart = tokenIn.balanceOf(address(maker));
        uint256 fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        uint256 makerOutputBalanceStart = tokenOut.balanceOf(address(maker));
        uint256 fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));

        // TODO: expand to allow for custom fillData in 3rd param
        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), maker, orderInfo.nonce);
        // execute order
        snapStart(string.concat(name(), "BaseExecuteSingle"));
        reactor.execute(signedOrder, address(fillContract), bytes(""));
        snapEnd();

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(maker)), makerOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Basic batch execute test
    // Two orders: 1. inputs = 1, outputs = 2, 2. inputs = 2, outputs = 4
    function testBaseExecuteBatch() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount * 3);
        tokenOut.mint(address(fillContract), 6 * 10 ** 18);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = inputAmount;
        inputAmounts[1] = 2 * inputAmount;

        // I dislike arrays in solidity ... there must be a better way to make a 2D array
        uint256[][] memory outputAmounts = new uint256[][](2);
        uint256[] memory o1 = new uint256[](1);
        uint256[] memory o2 = new uint256[](1);
        o1[0] = outputAmount;
        o2[0] = 2 * outputAmount;
        outputAmounts[0] = o1;
        outputAmounts[1] = o2;
        // This is very inefficient and we can add manually but I think it adds more clarify
        uint256 totalOutputAmount;
        for (uint256 i = 0; i < outputAmounts.length; i++) {
            for (uint256 j = 0; j < outputAmounts[i].length; j++) {
                totalOutputAmount += outputAmounts[i][j];
            }
        }
        uint256 totalInputAmount;
        for (uint256 i = 0; i < inputAmounts.length; i++) {
            totalInputAmount += inputAmounts[i];
        }

        OrderInfo[] memory infos = new OrderInfo[](2);
        infos[0] = OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(0);
        infos[1] = OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(1);

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) 
            = createAndSignBatchOrders(
                infos,
                inputAmounts,
                outputAmounts
            );
        vm.expectEmit(false, false, false, true);
        emit Fill(orderHashes[0], address(this), maker, infos[0].nonce);
        vm.expectEmit(false, false, false, true);
        emit Fill(orderHashes[1], address(this), maker, infos[1].nonce);

        snapStart(string.concat(name(), "BaseExecuteBatch"));
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
        snapEnd();

        assertEq(tokenOut.balanceOf(maker), totalOutputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
    }

    /// @dev Base test preventing signatures from being reused
    function testBaseExecuteSignatureReplay() public {
        // Seed both maker and fillContract with enough tokens
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(maker), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        tokenIn.forceApprove(maker, address(permit2), inputAmount);

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100);
        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(
            orderInfo,
            inputAmount, 
            outputAmount
        );

        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), maker, orderInfo.nonce);
        reactor.execute(signedOrder, address(fillContract), bytes(""));

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), inputAmount);

        bytes memory oldSignature = signedOrder.sig;
        // Create a new order, but use the previous signature
        (signedOrder, orderHash) = createAndSignOrder(
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(1),
            inputAmount, 
            outputAmount
        );
        signedOrder.sig = oldSignature;

        vm.expectRevert(InvalidSigner.selector);
        reactor.execute(signedOrder, address(fillContract), bytes(""));
    }

    /// @dev Base test preventing nonce reuse
    function testBaseNonceReuse() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(maker), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        // approve for 2 orders here
        tokenIn.forceApprove(maker, address(permit2), inputAmount * 2);

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(123);
        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(
            orderInfo,
            inputAmount, 
            outputAmount
        );

        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), maker, orderInfo.nonce);
        reactor.execute(signedOrder, address(fillContract), bytes(""));

        orderInfo = OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(123);
        (signedOrder, orderHash) = createAndSignOrder(
            orderInfo,
            inputAmount, 
            outputAmount
        );
        vm.expectRevert(InvalidNonce.selector);
        reactor.execute(signedOrder, address(fillContract), bytes(""));
    }
}
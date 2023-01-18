// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {Test} from "forge-std/Test.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {OrderInfo, InputToken, OutputToken} from '../../src/base/ReactorStructs.sol';
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {SignedOrder} from "../../src/base/ReactorStructs.sol";

struct IGenericOrder {
    OrderInfo info;
    InputToken input;
    OutputToken[] outputs;
}

abstract contract BaseReactorTest is ReactorEvents, Test {
    uint256 constant ONE = 10 ** 18;

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockFillContract fillContract;
    ISignatureTransfer permit2;
    BaseReactor reactor;
    uint256 makerPrivateKey;
    address maker;

    error InvalidNonce();
    
    /// @dev 
    function setUp() virtual public {}

    function createReactor() virtual public returns (BaseReactor) {}

    /// @dev returns (order, signature, orderHash, OrderInfo)
    // function createAndSignOrder() virtual public returns (bytes memory abiEncodedOrder, bytes memory sig, bytes32 orderHash, OrderInfo memory orderInfo) {}
    function createAndSignOrder(uint256 inputAmount, uint256 outputAmount) virtual public returns (bytes memory abiEncodedOrder, bytes memory sig, bytes32 orderHash, OrderInfo memory orderInfo) {}

    function testBaseExecute() virtual public {
        // Seed both maker and fillContract with enough tokens (important for dutch order)
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(maker), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        tokenIn.forceApprove(maker, address(permit2), inputAmount);

        reactor = createReactor();
        (bytes memory abiEncodedOrder, bytes memory sig, bytes32 orderHash, OrderInfo memory orderInfo) = createAndSignOrder(inputAmount, outputAmount);

        uint256 makerInputBalanceStart = tokenIn.balanceOf(address(maker));
        uint256 fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        uint256 makerOutputBalanceStart = tokenOut.balanceOf(address(maker));
        uint256 fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));

        // TODO: expand to allow for custom fillData in 3rd param
        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), maker, orderInfo.nonce);
        // execute order
        // TODO: allow for doing gas snapshot tests here custom to implementation
        reactor.execute(SignedOrder(abiEncodedOrder, sig), address(fillContract), bytes(""));

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(maker)), makerOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    function testBaseExecuteSignatureReplay() virtual public {
        // Seed both maker and fillContract with enough tokens (important for dutch order)
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(maker), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        tokenIn.forceApprove(maker, address(permit2), inputAmount);

        reactor = createReactor();
        (bytes memory abiEncodedOrder, bytes memory sig, bytes32 orderHash, OrderInfo memory orderInfo) = createAndSignOrder(inputAmount, outputAmount);

        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), maker, orderInfo.nonce);
        reactor.execute(SignedOrder(abiEncodedOrder, sig), address(fillContract), bytes(""));

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), inputAmount);

        // Create a new order, but use the previous signature
        bytes memory unusedSignature;
        (abiEncodedOrder, unusedSignature, orderHash, orderInfo) = createAndSignOrder(inputAmount, outputAmount);

        vm.expectRevert(InvalidNonce.selector);
        reactor.execute(SignedOrder(abiEncodedOrder, sig), address(fillContract), bytes(""));
    }
}
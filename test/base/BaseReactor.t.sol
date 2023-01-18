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
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockFillContract fillContract;
    ISignatureTransfer permit2;
    address maker;
    
    // TODO: make new generic type?
    BaseReactor reactor;
    
    // IMockGenericOrder , constructor can create limit order

    /// @dev 
    function setUp() virtual public {}

    function createReactor() virtual public returns (BaseReactor) {}

    /// @dev returns (order, signature, orderHash, OrderInfo)
    function createAndSignOrder() virtual public returns (bytes memory abiEncodedOrder, bytes memory sig, bytes32 orderHash, OrderInfo memory orderInfo) {}

    function testExecute() public {
        uint256 ONE = 10 ** 18;
        bytes memory abiEncodedOrder;
        bytes memory sig;
        bytes32 orderHash;
        OrderInfo memory orderInfo;

        tokenIn.forceApprove(maker, address(permit2), ONE);
        reactor = createReactor();
        (abiEncodedOrder, sig, orderHash, orderInfo) = createAndSignOrder();
        // execute order

        uint256 makerInputBalanceStart = tokenIn.balanceOf(address(maker));
        uint256 fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        uint256 makerOutputBalanceStart = tokenOut.balanceOf(address(maker));
        uint256 fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));

        // TODO: expand to allow for custom fillData in 3rd param
        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), maker, orderInfo.nonce);
        reactor.execute(SignedOrder(abiEncodedOrder, sig), address(fillContract), bytes(""));

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - ONE);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(maker)), makerOutputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - ONE);
    }

    // for signature re-use, call execute, listen for fill event, call again, expect fail
}
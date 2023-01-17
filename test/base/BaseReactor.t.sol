// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {Test} from "forge-std/Test.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {SignedOrder} from "../../src/base/ReactorStructs.sol";

abstract contract BaseReactorTest is Test {
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockFillContract fillContract;
    address maker;

    // for signature re-use, call execute, listen for fill event, call again, expect fail

    // IMockGenericOrder , constructor can create limit order

    /// @dev 
    function setUp() virtual public {}

    // function buildOrder() virtual public {}

    // call signature entry point, override in limit order and call func that exists on the limit order contract

    // test contracts here will use whatever virtual functions you define in the base contract, but can be different depending on set implementation 
}
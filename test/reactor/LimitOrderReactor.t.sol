// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {
    OrderInfo,
    Order,
    OrderExecution,
    Output,
    Signature,
    TokenAmount
} from "../../src/interfaces/ReactorStructs.sol";
import {OrderValidator} from "../../src/lib/OrderValidator.sol";
import {MockERC20} from "../../src/test/MockERC20.sol";
import {MockMaker} from "../../src/test/users/MockMaker.sol";
import {MockFillContract} from "../../src/test/MockFillContract.sol";
import {LimitOrderData} from "../../src/reactor/limit/LimitOrderStructs.sol";
import {LimitOrderReactor} from "../../src/reactor/limit/LimitOrderReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {OrderExecutionBuilder} from "../util/OrderExecutionBuilder.sol";

contract LimitOrderReactorTest is Test {
    using OrderExecutionBuilder for OrderExecution;

    uint256 constant ONE = 10 ** 18;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockMaker maker;
    LimitOrderReactor reactor;

    function setUp() public {
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        maker = new MockMaker();
        tokenIn.mint(address(maker), ONE);
        tokenOut.mint(address(fillContract), ONE);
        reactor = new LimitOrderReactor();
    }

    function testExecute() public {
        maker.approve(address(tokenIn), address(reactor), ONE);
        LimitOrderData memory limitOrderData = LimitOrderData({
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });

        OrderExecution memory execution = OrderExecutionBuilder.init()
            .withReactor(address(reactor)).withOfferer(address(maker)).withData(
            abi.encode(limitOrderData)
        ).withFillContract(address(fillContract));

        uint256 makerInputBalanceStart = tokenIn.balanceOf(address(maker));
        uint256 fillContractInputBalanceStart =
            tokenIn.balanceOf(address(fillContract));
        uint256 makerOutputBalanceStart = tokenOut.balanceOf(address(maker));
        uint256 fillContractOutputBalanceStart =
            tokenOut.balanceOf(address(fillContract));

        reactor.execute(execution);

        assertEq(
            tokenIn.balanceOf(address(maker)), makerInputBalanceStart - ONE
        );
        assertEq(
            tokenIn.balanceOf(address(fillContract)),
            fillContractInputBalanceStart + ONE
        );
        assertEq(
            tokenOut.balanceOf(address(maker)), makerOutputBalanceStart + ONE
        );
        assertEq(
            tokenOut.balanceOf(address(fillContract)),
            fillContractOutputBalanceStart - ONE
        );
    }
}

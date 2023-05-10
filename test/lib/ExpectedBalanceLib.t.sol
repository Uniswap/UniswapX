// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {OrderInfo, ResolvedOrder, OutputToken} from "../../src/base/ReactorStructs.sol";
import {ExpectedBalance, ExpectedBalanceLib} from "../../src/lib/ExpectedBalanceLib.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {MockExpectedBalanceLib} from "../util/mock/MockExpectedBalanceLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";

contract ExpectedBalanceTest is Test {
    using ExpectedBalanceLib for ResolvedOrder[];
    using ExpectedBalanceLib for ExpectedBalance[];
    using OrderInfoBuilder for OrderInfo;
    using ArrayBuilder for uint256[];
    using ArrayBuilder for address[];

    struct TestGetExpectedBalanceConfig {
        address recipient;
        uint64 amount;
        uint64 preBalance;
        bool useToken1;
    }

    address recipient1;
    address recipient2;
    address[] recipientsInOrder;
    address[] tokensInOrder;
    MockERC20 token1Contract;
    MockERC20 token2Contract;
    address token1;
    address token2;
    MockExpectedBalanceLib mockExpectedBalanceLib;

    function setUp() public {
        recipient1 = makeAddr("recipient1");
        recipient2 = makeAddr("recipient2");
        token1Contract = new MockERC20("Mock1", "MOCK1", 18);
        token2Contract = new MockERC20("Mock2", "MOCK2", 18);
        mockExpectedBalanceLib = new MockExpectedBalanceLib();

        // ensure addresses are in order
        require(recipient1 != recipient2);
        require(address(token1Contract) != address(token2Contract));
        if (address(token2Contract) < address(token1Contract)) {
            MockERC20 tempToken = token1Contract;
            token1Contract = token2Contract;
            token2Contract = tempToken;
        }
        if (recipient2 < recipient1) {
            address tempRecipient = recipient1;
            recipient1 = recipient2;
            recipient2 = tempRecipient;
        }

        token1 = address(token1Contract);
        token2 = address(token2Contract);

        recipientsInOrder = ArrayBuilder.fill(1, recipient1).push(recipient2);

        tokensInOrder = ArrayBuilder.fill(1, token1).push(token2);
    }

    function testGetExpectedBalanceSingle(uint256 amount) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        orders[0].outputs = OutputsBuilder.single(token1, amount, recipient1);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 1);
        assertEq(expectedBalances[0].token, token1);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, amount);
    }

    function testGetExpectedBalanceSingleNative(uint256 amount) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        orders[0].outputs = OutputsBuilder.single(NATIVE, amount, recipient1);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 1);
        assertEq(expectedBalances[0].token, NATIVE);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, amount);
    }

    function testGetExpectedBalanceSingleWithPreBalance(uint128 preAmount, uint128 amount) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        token1Contract.mint(recipient1, preAmount);
        orders[0].outputs = OutputsBuilder.single(token1, amount, recipient1);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 1);
        assertEq(expectedBalances[0].token, token1);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, uint256(amount) + preAmount);
    }

    function testGetExpectedBalanceSingleWithPreBalanceNative(uint128 preAmount, uint128 amount) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        vm.deal(recipient1, preAmount);
        orders[0].outputs = OutputsBuilder.single(NATIVE, amount, recipient1);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 1);
        assertEq(expectedBalances[0].token, NATIVE);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, uint256(amount) + preAmount);
    }

    function testGetExpectedBalanceMultiOutput(uint128 amount1, uint128 amount2) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        uint256[] memory amounts = ArrayBuilder.fill(1, amount1).push(amount2);
        orders[0].outputs = OutputsBuilder.multiple(token1, amounts, recipient1);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 1);
        assertEq(expectedBalances[0].token, token1);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, uint256(amount1) + amount2);
    }

    function testGetExpectedBalanceMultiOutputSomeDuplicate(uint128 amount) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        uint256[] memory amounts = ArrayBuilder.fill(3, uint256(amount));
        address[] memory tokens = ArrayBuilder.fill(3, NATIVE);
        address[] memory recipients = ArrayBuilder.fill(1, recipient1).push(recipient2).push(recipient2);
        orders[0].outputs = OutputsBuilder.multiple(tokens, amounts, recipients);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 2);
        assertEq(expectedBalances[0].token, NATIVE);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, amount);
        assertEq(expectedBalances[1].token, NATIVE);
        assertEq(expectedBalances[1].recipient, recipient2);
        assertEq(expectedBalances[1].expectedBalance, uint256(amount) * 2);
    }

    function testGetExpectedBalanceMultiOutputWithPreBalance(uint128 preAmount, uint64 amount1, uint64 amount2)
        public
    {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        token1Contract.mint(recipient1, preAmount);
        uint256[] memory amounts = ArrayBuilder.fill(1, amount1).push(amount2);
        orders[0].outputs = OutputsBuilder.multiple(token1, amounts, recipient1);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 1);
        assertEq(expectedBalances[0].token, token1);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, uint256(preAmount) + amount1 + amount2);
    }

    function testGetExpectedBalanceMultiOutputMultiToken(uint256 amount) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        address[] memory recipients = ArrayBuilder.fill(2, recipient1);
        uint256[] memory amounts = ArrayBuilder.fill(2, amount);
        orders[0].outputs = OutputsBuilder.multiple(tokensInOrder, amounts, recipients);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 2);
        assertEq(expectedBalances[0].token, token1);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, amount);
        assertEq(expectedBalances[1].token, token2);
        assertEq(expectedBalances[1].recipient, recipient1);
        assertEq(expectedBalances[1].expectedBalance, amount);
    }

    function testGetExpectedBalanceMultipleRecipients(uint128 amount1, uint128 amount2) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        orders[0].outputs = new OutputToken[](2);
        orders[0].outputs[0] = OutputToken(token1, amount1, recipient1, false);
        orders[0].outputs[1] = OutputToken(token1, amount2, recipient2, false);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 2);
        assertEq(expectedBalances[0].token, token1);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, amount1);
        assertEq(expectedBalances[1].token, token1);
        assertEq(expectedBalances[1].recipient, recipient2);
        assertEq(expectedBalances[1].expectedBalance, amount2);
    }

    function testGetExpectedBalanceMultipleRecipientsWithPreBalance(uint128 preAmount, uint128 amount1, uint128 amount2)
        public
    {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        token1Contract.mint(recipient1, preAmount);
        token1Contract.mint(recipient2, preAmount);
        orders[0].outputs = new OutputToken[](2);
        orders[0].outputs[0] = OutputToken(token1, amount1, recipient1, false);
        orders[0].outputs[1] = OutputToken(token1, amount2, recipient2, false);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 2);
        assertEq(expectedBalances[0].token, token1);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, uint256(preAmount) + amount1);
        assertEq(expectedBalances[1].token, token1);
        assertEq(expectedBalances[1].recipient, recipient2);
        assertEq(expectedBalances[1].expectedBalance, uint256(preAmount) + amount2);
    }

    function testGetExpectedBalanceMultiOrder(uint128 amount1, uint128 amount2) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](2);
        orders[0].outputs = OutputsBuilder.single(token1, amount1, recipient1);
        orders[1].outputs = OutputsBuilder.single(token1, amount2, recipient1);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 1);
        assertEq(expectedBalances[0].token, token1);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, uint256(amount1) + amount2);
    }

    function testGetExpectedBalanceMultiOrderMultiOutput(uint64 amount1, uint64 amount2) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;
        orders[0].outputs = OutputsBuilder.multiple(token1, amounts, recipient1);
        orders[1].outputs = OutputsBuilder.multiple(token1, amounts, recipient1);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 1);
        assertEq(expectedBalances[0].token, token1);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, uint256(amount1) + amount2 + amount1 + amount2);
    }

    function testGetExpectedBalanceMultiOrderMultiRecipients(uint128 amount1, uint128 amount2) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](2);
        orders[0].outputs = OutputsBuilder.single(token1, amount1, recipient1);
        orders[1].outputs = OutputsBuilder.single(token1, amount2, recipient2);

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertEq(expectedBalances.length, 2);
        assertEq(expectedBalances[0].token, token1);
        assertEq(expectedBalances[0].recipient, recipient1);
        assertEq(expectedBalances[0].expectedBalance, uint256(amount1));
        assertEq(expectedBalances[1].token, token1);
        assertEq(expectedBalances[1].recipient, recipient2);
        assertEq(expectedBalances[1].expectedBalance, uint256(amount2));
    }

    // asserting no reverts and sane handling on arbitrary output lists
    function testGetExpectedBalanceManyOutputs(TestGetExpectedBalanceConfig[] memory test) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        orders[0].outputs = new OutputToken[](test.length);
        for (uint256 i = 0; i < test.length; i++) {
            TestGetExpectedBalanceConfig memory config = test[i];
            address token = config.useToken1 ? token1 : token2;
            MockERC20(token).mint(config.recipient, config.preBalance);
            orders[0].outputs[i] = OutputToken(token, config.amount, config.recipient, false);
        }

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertFuzzSanity(test, expectedBalances);
    }

    // asserting no reverts and sane handling on arbitrary output lists
    function testGetExpectedBalanceManyOrders(TestGetExpectedBalanceConfig[] memory test) public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](test.length);
        for (uint256 i = 0; i < test.length; i++) {
            TestGetExpectedBalanceConfig memory config = test[i];
            address token = config.useToken1 ? token1 : token2;
            MockERC20(token).mint(config.recipient, config.preBalance);
            orders[i].outputs = OutputsBuilder.single(token, config.amount, config.recipient);
        }

        ExpectedBalance[] memory expectedBalances = orders.getExpectedBalances();
        assertFuzzSanity(test, expectedBalances);
    }

    function assertFuzzSanity(TestGetExpectedBalanceConfig[] memory test, ExpectedBalance[] memory expectedBalances)
        internal
    {
        assertLe(expectedBalances.length, test.length);

        // assert each recipient in test with nonzero value has an entry
        uint256 totalSum1;
        uint256 totalSum2;
        for (uint256 i = 0; i < test.length; i++) {
            TestGetExpectedBalanceConfig memory config = test[i];
            config.useToken1
                ? totalSum1 += uint256(config.amount) + config.preBalance
                : totalSum2 += uint256(config.amount) + config.preBalance;

            if (config.amount == 0) {
                continue;
            }
            bool found = false;
            for (uint256 j = 0; j < expectedBalances.length; j++) {
                address token = config.useToken1 ? token1 : token2;
                if (expectedBalances[j].recipient == config.recipient && expectedBalances[j].token == token) {
                    assertGe(expectedBalances[j].expectedBalance, uint256(config.amount) + config.preBalance);
                    found = true;
                    break;
                }
            }
            assertTrue(found);
        }

        // assert totalSums
        uint256 sum1;
        uint256 sum2;
        for (uint256 i = 0; i < expectedBalances.length; i++) {
            if (expectedBalances[i].token == token1) {
                sum1 += expectedBalances[i].expectedBalance;
            } else {
                sum2 += expectedBalances[i].expectedBalance;
            }
        }
        assertEq(sum1, totalSum1);
        assertEq(sum2, totalSum2);
    }

    // check tests

    function testCheck(uint256 expected, uint256 balance) public {
        vm.assume(balance >= expected);
        ExpectedBalance[] memory expectedBalances = new ExpectedBalance[](1);
        expectedBalances[0] = ExpectedBalance(recipient1, token1, expected);
        token1Contract.mint(recipient1, balance);
        mockExpectedBalanceLib.check(expectedBalances);
    }

    function testCheckNative(uint256 expected, uint256 balance) public {
        vm.assume(balance >= expected);
        ExpectedBalance[] memory expectedBalances = new ExpectedBalance[](1);
        expectedBalances[0] = ExpectedBalance(recipient1, NATIVE, expected);
        vm.deal(recipient1, balance);
        mockExpectedBalanceLib.check(expectedBalances);
    }

    function testCheckMany(uint128 expected, uint128 balance) public {
        vm.assume(balance >= expected);
        ExpectedBalance[] memory expectedBalances = new ExpectedBalance[](4);
        expectedBalances[0] = ExpectedBalance(recipient1, token1, expected);
        expectedBalances[1] = ExpectedBalance(recipient1, token2, expected);
        expectedBalances[2] = ExpectedBalance(recipient2, token1, expected);
        expectedBalances[3] = ExpectedBalance(recipient2, token2, expected);
        token1Contract.mint(recipient1, balance);
        token2Contract.mint(recipient1, balance);
        token1Contract.mint(recipient2, balance);
        token2Contract.mint(recipient2, balance);
        mockExpectedBalanceLib.check(expectedBalances);
    }

    function testCheckInsufficientOutput(uint256 expected, uint256 balance) public {
        vm.assume(balance < expected);
        ExpectedBalance[] memory expectedBalances = new ExpectedBalance[](1);
        expectedBalances[0] = ExpectedBalance(recipient1, token1, expected);
        token1Contract.mint(recipient1, balance);
        vm.expectRevert(ExpectedBalanceLib.InsufficientOutput.selector);
        mockExpectedBalanceLib.check(expectedBalances);
    }

    function testCheckInsufficientOutputNative(uint256 expected, uint256 balance) public {
        vm.assume(balance < expected);
        ExpectedBalance[] memory expectedBalances = new ExpectedBalance[](1);
        expectedBalances[0] = ExpectedBalance(recipient1, NATIVE, expected);
        vm.deal(recipient1, balance);
        vm.expectRevert(ExpectedBalanceLib.InsufficientOutput.selector);
        mockExpectedBalanceLib.check(expectedBalances);
    }

    function testCheckInsufficientOutputFirstOfMany(uint128 expected, uint128 balance) public {
        vm.assume(balance < expected);
        ExpectedBalance[] memory expectedBalances = new ExpectedBalance[](3);
        expectedBalances[0] = ExpectedBalance(recipient1, token1, expected);
        expectedBalances[1] = ExpectedBalance(recipient2, token1, expected);
        expectedBalances[2] = ExpectedBalance(recipient2, token2, expected);
        token1Contract.mint(recipient1, balance);
        token1Contract.mint(recipient2, expected);
        token2Contract.mint(recipient2, expected);
        vm.expectRevert(ExpectedBalanceLib.InsufficientOutput.selector);
        mockExpectedBalanceLib.check(expectedBalances);
    }

    function testCheckInsufficientOutputMiddleOfMany(uint128 expected, uint128 balance) public {
        vm.assume(balance < expected);
        ExpectedBalance[] memory expectedBalances = new ExpectedBalance[](3);
        expectedBalances[0] = ExpectedBalance(recipient1, token1, expected);
        expectedBalances[1] = ExpectedBalance(recipient2, token1, expected);
        expectedBalances[2] = ExpectedBalance(recipient2, token2, expected);
        token1Contract.mint(recipient1, expected);
        token1Contract.mint(recipient2, balance);
        token2Contract.mint(recipient2, expected);
        vm.expectRevert(ExpectedBalanceLib.InsufficientOutput.selector);
        mockExpectedBalanceLib.check(expectedBalances);
    }

    function testCheckInsufficientOutputLastOfMany(uint128 expected, uint128 balance) public {
        vm.assume(balance < expected);
        ExpectedBalance[] memory expectedBalances = new ExpectedBalance[](3);
        expectedBalances[0] = ExpectedBalance(recipient1, token1, expected);
        expectedBalances[1] = ExpectedBalance(recipient2, token1, expected);
        expectedBalances[2] = ExpectedBalance(recipient2, token2, expected);
        token1Contract.mint(recipient1, expected);
        token1Contract.mint(recipient2, expected);
        token2Contract.mint(recipient2, balance);
        vm.expectRevert(ExpectedBalanceLib.InsufficientOutput.selector);
        mockExpectedBalanceLib.check(expectedBalances);
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {DeployPermit2} from "../util/DeployPermit2.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";

import {Reactor} from "../../src/v4/Reactor.sol";
import {TokenTransferHook} from "../../src/v4/hooks/TokenTransferHook.sol";
import {SignedOrder, InputToken} from "../../src/base/ReactorStructs.sol";
import {OrderInfo} from "../../src/v4/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../v4/util/OrderInfoBuilder.sol";
import {MockAuctionResolver} from "../v4/util/mock/MockAuctionResolver.sol";
import {MockOrder, MockOrderLib} from "../v4/util/mock/MockOrderLib.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";

/// @notice V4 native-output tests
contract EthOutputV4Test is Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using MockOrderLib for MockOrder;

    address internal constant PROTOCOL_FEE_OWNER = address(1);

    MockERC20 internal tokenIn;
    IPermit2 internal permit2;
    Reactor internal reactor;
    MockAuctionResolver internal mockResolver;
    TokenTransferHook internal tokenTransferHook;

    uint256 internal swapperPrivateKey;
    address internal swapper;
    address internal directFiller;

    function setUp() public {
        // Make ETH balance assertions stable (ignore gas costs).
        vm.txGasPrice(0);

        tokenIn = new MockERC20("Input", "IN", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        directFiller = address(888);

        permit2 = IPermit2(deployPermit2());
        reactor = new Reactor(PROTOCOL_FEE_OWNER, permit2);
        mockResolver = new MockAuctionResolver();
        tokenTransferHook = new TokenTransferHook(permit2, reactor);
    }

    // Fill 1 order with requested output = 2 ETH.
    function testEth1Output() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 2 * inputAmount;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(swapper, inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);
        vm.deal(directFiller, outputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = _createAndSignOrder(order);

        uint256 swapperEthBefore = swapper.balance;
        uint256 fillerEthBefore = directFiller.balance;

        vm.prank(directFiller);
        reactor.execute{value: outputAmount}(signedOrder);

        assertEq(swapper.balance, swapperEthBefore + outputAmount);
        assertEq(directFiller.balance, fillerEthBefore - outputAmount);
    }

    function testExcessETHIsReturned() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 2 * inputAmount;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(swapper, inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);
        vm.deal(directFiller, outputAmount * 2);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = _createAndSignOrder(order);

        uint256 fillerEthBefore = directFiller.balance;

        vm.prank(directFiller);
        reactor.execute{value: outputAmount * 2}(signedOrder);

        // check directFiller received refund (only outputAmount should be spent)
        assertEq(directFiller.balance, fillerEthBefore - outputAmount);
        assertEq(address(reactor).balance, 0);
    }

    // Same as testEth1Output, but reverts because directFiller doesn't send enough ether
    function testEth1OutputInsufficientEthSent() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 2 * inputAmount;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(swapper, inputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);
        vm.deal(directFiller, outputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = _createAndSignOrder(order);

        vm.prank(directFiller);
        vm.expectRevert(); // CurrencyLibrary.NativeTransferFailed (selector differs by version; keep broad)
        reactor.execute{value: outputAmount - 1}(signedOrder);
    }

    function _createAndSignOrder(MockOrder memory mockOrder)
        internal
        view
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        orderHash = mockOrder.witnessHash(address(mockOrder.info.auctionResolver));
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), mockOrder);
        bytes memory orderData = abi.encode(mockOrder);
        bytes memory encodedOrder = abi.encode(address(mockResolver), orderData);
        signedOrder = SignedOrder(encodedOrder, sig);
    }
}


// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {OrderInfo, InputToken, OutputToken, ResolvedRelayOrder, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockFeeController} from "../util/mock/MockFeeController.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {RelayOrderReactor} from "../../src/reactors/RelayOrderReactor.sol";

contract RelayOrderReactorTest is PermitSignature, DeployPermit2, GasSnapshot, ReactorEvents, Test {
    using OrderInfoBuilder for OrderInfo;
    using RelayOrderLib for RelayOrder;
    using ArrayBuilder for uint256[];
    using ArrayBuilder for uint256[][];

    uint256 constant ONE = 10 ** 18;
    address internal constant PROTOCOL_FEE_OWNER = address(1);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockERC20 tokenOut2;
    IPermit2 permit2;
    MockFeeController feeController;
    address feeRecipient;
    BaseReactor reactor;
    uint256 swapperPrivateKey;
    address swapper;

    error InvalidNonce();
    error InvalidSigner();
    string constant LIMIT_ORDER_TYPE_NAME = "RelayOrder";

    constructor() {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        tokenOut2 = new MockERC20("Output2", "OUT2", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        permit2 = IPermit2(deployPermit2());
        feeRecipient = makeAddr("feeRecipient");
        feeController = new MockFeeController(feeRecipient);
        reactor = createReactor();
    }

    function setUp() public {
        tokenIn.mint(address(swapper), ONE);
    }

    function name() public pure override returns (string memory) {
        return "RelayOrderReactor";
    }

    function createReactor() public override returns (BaseReactor) {
        return new RelayOrderReactor(permit2, PROTOCOL_FEE_OWNER, universalRouter);
    }

    /// @dev Create and return a basic RelayOrder along with its signature, hash, and orderInfo
    function createAndSignOrder(ResolvedRelayOrder memory request)
        public
        view
        override
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        RelayOrder memory order = RelayOrder({info: request.info, input: request.input, outputs: request.outputs});
        orderHash = order.hash();
        return (SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)), orderHash);
    }

    function testExecuteWithValidationContract() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(address(swapper)).withValidationContract(
                additionalValidationContract
                ),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));
        uint256 fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));

        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), swapper, order.info.nonce);

        fillContract.execute(SignedOrder(abi.encode(order), sig));

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - ONE);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - ONE);
    }

    function testExecuteInsufficientOutput() public {
        MockFillContractWithOutputOverride fill = new MockFillContractWithOutputOverride(address(reactor));
        tokenOut.mint(address(fill), ONE);
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(address(swapper)).withValidationContract(
                additionalValidationContract
                ),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE * 2, address(swapper))
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);

        fill.setOutputAmount(ONE);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        fillContract.execute(SignedOrder(abi.encode(order), sig));
    }

    function testExecuteWithDuplicateOutputs() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ONE / 2;
        amounts[1] = ONE / 2;
        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(address(swapper)).withValidationContract(
                additionalValidationContract
                ),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.multiple(address(tokenOut), amounts, address(swapper))
        });
        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));
        uint256 fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));

        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), swapper, order.info.nonce);

        fillContract.execute(SignedOrder(abi.encode(order), sig));

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - ONE);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - ONE);
    }

    function testExecuteWithValidationContractChangeSig() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(address(swapper)).withValidationContract(
                additionalValidationContract
                ),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);

        // change validation contract, ensure that sig fails
        order.info.additionalValidationContract = IValidationCallback(address(0));

        vm.expectRevert(InvalidSigner.selector);
        fillContract.execute(SignedOrder(abi.encode(order), sig));
    }

    function testExecuteWithFeeOutput() public {
        address feeRecipient = address(1);
        MockFeeController feeController = new MockFeeController(feeRecipient);
        vm.prank(PROTOCOL_FEE_OWNER);
        reactor.setProtocolFeeController(address(feeController));
        uint256 feeBps = 5;
        feeController.setFee(tokenIn, address(tokenOut), feeBps);
        tokenOut.mint(address(fillContract), ONE);

        tokenIn.forceApprove(swapper, address(permit2), ONE);
        tokenIn.forceApprove(swapper, address(permit2), ONE);

        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(address(swapper)),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));
        uint256 fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));

        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this), swapper, order.info.nonce);

        fillContract.execute(SignedOrder(abi.encode(order), sig));

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - ONE);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + ONE);
        assertEq(
            tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - (ONE * (feeBps + 10000) / 10000)
        );
        assertEq(tokenOut.balanceOf(address(feeRecipient)), ONE * feeBps / 10000);
    }

    function testExecuteInsufficientPermit() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(address(swapper)),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });

        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(
            swapperPrivateKey, address(permit2), order.info, address(tokenIn), ONE / 2, LIMIT_ORDER_TYPE_HASH, orderHash
        );

        vm.expectRevert(InvalidSigner.selector);
        fillContract.execute(SignedOrder(abi.encode(order), sig));
    }

    function testExecuteIncorrectSpender() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(address(swapper)),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });

        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(
            swapperPrivateKey,
            address(permit2),
            OrderInfoBuilder.init(address(this)).withSwapper(address(swapper)),
            address(order.input.token),
            order.input.amount,
            LIMIT_ORDER_TYPE_HASH,
            orderHash
        );

        vm.expectRevert(InvalidSigner.selector);
        fillContract.execute(SignedOrder(abi.encode(order), sig));
    }

    function testExecuteIncorrectToken() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        RelayOrder memory order = RelayOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(address(swapper)),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });

        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(
            swapperPrivateKey, address(permit2), order.info, address(tokenOut), ONE, LIMIT_ORDER_TYPE_HASH, orderHash
        );
        vm.expectRevert(InvalidSigner.selector);
        fillContract.execute(SignedOrder(abi.encode(order), sig));
    }
}

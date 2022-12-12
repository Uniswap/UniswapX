import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Permit2} from "permit2/Permit2.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchInput} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchLimitOrder, DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ExclusiveFillerValidation} from "../../src/sample-validation-contracts/ExclusiveFillerValidation.sol";
import {OrderInfoLib} from "../../src/lib/OrderInfoLib.sol";

contract ExclusiveFillerValidationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using DutchLimitOrderLib for DutchLimitOrder;

    address constant PROTOCOL_FEE_RECIPIENT = address(1);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 makerPrivateKey;
    address maker;
    DutchLimitOrderReactor reactor;
    Permit2 permit2;
    ExclusiveFillerValidation exclusiveFillerValidation;

    function setUp() public {
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        permit2 = new Permit2();
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        exclusiveFillerValidation = new ExclusiveFillerValidation();
    }

    // Test exclusive filler validation contract succeeds
    function testExclusiveFillerSucceeds() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp + 50)
                ),
            startTime: block.timestamp,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenOut.balanceOf(maker), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    // The filler is incorrectly address(0x123)
    function testExclusiveFillerFails() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp + 50)
                ),
            startTime: block.timestamp,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        vm.prank(address(0x123));
        vm.expectRevert(OrderInfoLib.ValidationFailed.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
    }

    // Ensure a different filler (not the one encoded in validationData) is able to execute after last exclusive
    // timestamp
    function testExclusiveFillerSucceedsPastExclusiveTimestamp() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        vm.warp(1000);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
                .withValidationContract(address(exclusiveFillerValidation)).withValidationData(
                abi.encode(address(this), block.timestamp - 50)
                ),
            startTime: block.timestamp,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        vm.prank(address(0x123));
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenOut.balanceOf(maker), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }
}

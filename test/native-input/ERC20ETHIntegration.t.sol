// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {ERC20ETH} from "../../lib/calibur/lib/erc20-eth/src/ERC20Eth.sol";
import {ERC7914} from "../../lib/calibur/src/ERC7914.sol";
import {DelegationHandler} from "./DelegationHandler.sol";
import {
    V3DutchOrder,
    V3DutchOrderLib,
    V3DutchOrderReactor,
    CosignerData
} from "../../src/reactors/V3DutchOrderReactor.sol";
import {V3DutchOutput, V3DutchInput} from "../../src/lib/V3DutchOrderLib.sol";
import {
    PriorityOrder,
    PriorityOrderLib,
    PriorityInput,
    PriorityOutput,
    PriorityCosignerData
} from "../../src/lib/PriorityOrderLib.sol";
import {PriorityOrderReactor} from "../../src/reactors/PriorityOrderReactor.sol";
import {PriorityFeeLib} from "../../src/lib/PriorityFeeLib.sol";
import {
    V2DutchOrder,
    V2DutchOrderLib,
    V2DutchOrderReactor,
    CosignerData as V2CosignerData,
    DutchInput,
    DutchOutput
} from "../../src/reactors/V2DutchOrderReactor.sol";
import {OrderInfo, InputToken, SignedOrder, OutputToken} from "../../src/base/ReactorStructs.sol";
import {CurrencyLibrary, NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {CurveBuilder} from "../util/CurveBuilder.sol";
import {Solarray} from "solarray/Solarray.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ICalibur} from "../../lib/calibur/src/interfaces/ICalibur.sol";
import {Constants} from "../../lib/calibur/test/utils/Constants.sol";
import {EntryPoint} from "../../lib/calibur/lib/account-abstraction/contracts/core/EntryPoint.sol";
import {TestKeyManager, TestKey} from "../../lib/calibur/test/utils/TestKeyManager.sol";
import {KeyType} from "../../lib/calibur/src/libraries/KeyLib.sol";

// Tests each reactor with native ETH input.
contract ERC20ETHIntegrationTest is Test, DeployPermit2, PermitSignature, DelegationHandler {
    using OrderInfoBuilder for OrderInfo;
    using V3DutchOrderLib for V3DutchOrder;
    using PriorityOrderLib for PriorityOrder;
    using PriorityFeeLib for PriorityOutput;
    using V2DutchOrderLib for V2DutchOrder;

    ERC20ETH public erc20eth;
    ERC7914 public account;
    uint256 constant cosignerPrivateKey = 0x99999999;
    MockERC20 tokenOut;
    address internal constant PROTOCOL_FEE_OWNER = address(1);
    MockFillContract fillContract;
    IPermit2 permit2;

    function setUp() public {
        permit2 = IPermit2(deployPermit2());

        tokenOut = new MockERC20("Output", "OUT", 18);

        // Create the smart wallet account using signerPrivateKey
        setUpDelegation();

        // Deploy ERC20ETH
        erc20eth = new ERC20ETH();
    }

    function test_V2DutchOrderWithNativeInput() public {
        // Deploy reactor
        V2DutchOrderReactor v2DutchOrderReactor = new V2DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);

        // Create fillContract with the reactor address
        fillContract = new MockFillContract(address(v2DutchOrderReactor));

        // Fund the swapper with ETH
        uint256 totalAmount = 1 ether;
        uint256 swapAmount = 0.5 ether;
        vm.deal(address(signerAccount), totalAmount);

        // Approve ERC20ETH to use signerAccount's native ETH
        vm.prank(address(signerAccount));
        signerAccount.approveNative(address(erc20eth), type(uint256).max);

        // Give filler some output
        uint256 totalFillerAmount = 0.6 ether;
        uint256 outputAmount = 0.5 ether;
        tokenOut.mint(address(fillContract), totalFillerAmount);

        // Create the V2 Dutch order
        DutchOutput[] memory outputs =
            OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, address(signerAccount));

        V2CosignerData memory cosignerData = V2CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: ArrayBuilder.fill(1, 0)
        });

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(v2DutchOrderReactor)).withSwapper(address(signerAccount)),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(
                ERC20(address(erc20eth)), // Input is native ETH
                swapAmount,
                swapAmount
            ),
            baseOutputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });

        // Sign the order
        bytes32 orderHash = order.hash();
        order.cosignature = cosignV2Order(orderHash, order.cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(signerPrivateKey, address(permit2), order));

        // Execute the order
        fillContract.execute(signedOrder);

        // Verify the balances
        // Swapper should have totalAmount - swapAmount ETH left and have received outputAmount tokenOut
        assertEq(address(signerAccount).balance, totalAmount - swapAmount);
        assertEq(tokenOut.balanceOf(address(signerAccount)), outputAmount);

        // Filler should have received the swapAmount ETH
        assertEq(address(fillContract).balance, swapAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), totalFillerAmount - outputAmount);
    }

    function test_V3DutchOrderWithNativeInput() public {
        // Deploy reactor
        V3DutchOrderReactor v3DutchOrderReactor = new V3DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);

        // Create fillContract with the reactor address
        fillContract = new MockFillContract(address(v3DutchOrderReactor));

        // Fund the swapper with ETH
        uint256 totalAmount = 1 ether;
        uint256 swapAmount = 0.5 ether;
        vm.deal(address(signerAccount), totalAmount);

        // Approve ERC20ETH to use signerAccount's native ETH
        vm.prank(address(signerAccount));
        signerAccount.approveNative(address(erc20eth), type(uint256).max);

        // Give filler some output
        uint256 outputAmount = 0.5 ether;
        tokenOut.mint(address(fillContract), outputAmount);

        // Create the order
        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(v3DutchOrderReactor)).withSwapper(address(signerAccount)),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: V3DutchInput(
                ERC20(address(erc20eth)), // Input is native ETH
                swapAmount,
                CurveBuilder.emptyCurve(),
                swapAmount,
                0
            ),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                address(tokenOut), outputAmount, outputAmount, CurveBuilder.emptyCurve(), address(signerAccount)
            ),
            cosignerData: CosignerData({
                decayStartBlock: block.number,
                exclusiveFiller: address(0),
                exclusivityOverrideBps: 0,
                inputAmount: swapAmount,
                outputAmounts: ArrayBuilder.fill(1, outputAmount)
            }),
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });

        // Sign the order
        bytes32 orderHash = order.hash();
        order.cosignature = cosignOrder(orderHash, order.cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(signerPrivateKey, address(permit2), order));

        // Execute the order
        fillContract.execute(signedOrder);

        // Verify the balances
        // Swapper should have totalAmount - swapAmount ETH left and have received outputAmount tokenOut
        assertEq(address(signerAccount).balance, totalAmount - swapAmount);
        assertEq(tokenOut.balanceOf(address(signerAccount)), outputAmount);

        // Filler should have 0 tokenOut left and received the swapAmount ETH
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);
        assertEq(address(fillContract).balance, swapAmount);
    }

    function test_PriorityOrderWithNativeInput() public {
        // Deploy reactor
        PriorityOrderReactor priorityOrderReactor = new PriorityOrderReactor(permit2, PROTOCOL_FEE_OWNER);

        // Create fillContract with the reactor address
        fillContract = new MockFillContract(address(priorityOrderReactor));

        // Set up priority fee like the reference test
        uint256 baselinePriorityFeeWei = 1 gwei;
        uint256 priorityFee = baselinePriorityFeeWei + 100 wei;
        vm.txGasPrice(priorityFee);

        // Fund the swapper with ETH
        uint256 totalAmount = 1 ether;
        uint256 swapAmount = 0.5 ether;
        vm.deal(address(signerAccount), totalAmount);

        // Approve ERC20ETH to use signerAccount's native ETH
        vm.prank(address(signerAccount));
        signerAccount.approveNative(address(erc20eth), type(uint256).max);

        // Give filler some output
        uint256 totalFillerAmount = 0.6 ether;
        uint256 outputAmount = 0.5 ether;
        tokenOut.mint(address(fillContract), totalFillerAmount);

        // Create the priority order
        PriorityOutput[] memory outputs = OutputsBuilder.singlePriority(
            address(tokenOut),
            outputAmount,
            1, // priority fee scaling
            address(signerAccount)
        );

        // Calculate the scaled output amount like the reference test
        uint256 scaledOutputAmount = PriorityFeeLib.scale(outputs[0], priorityFee - baselinePriorityFeeWei).amount;

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrder memory order = PriorityOrder({
            info: OrderInfoBuilder.init(address(priorityOrderReactor)).withSwapper(address(signerAccount)),
            cosigner: vm.addr(cosignerPrivateKey),
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: baselinePriorityFeeWei,
            input: PriorityInput({
                token: ERC20(address(erc20eth)), // Input is native ETH
                amount: swapAmount,
                mpsPerPriorityFeeWei: 0
            }),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });

        // Sign the order
        bytes32 orderHash = order.hash();
        order.cosignature = cosignPriorityOrder(orderHash, order.cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(signerPrivateKey, address(permit2), order));

        // Execute the order
        fillContract.execute(signedOrder);

        // Verify the balances
        // Swapper should have totalAmount - swapAmount ETH left and have received scaledOutputAmount tokenOut
        assertEq(address(signerAccount).balance, totalAmount - swapAmount);
        assertEq(tokenOut.balanceOf(address(signerAccount)), scaledOutputAmount);

        // Filler should have received the swapAmount ETH
        assertEq(address(fillContract).balance, swapAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), totalFillerAmount - scaledOutputAmount);
    }

    function cosignV2Order(bytes32 orderHash, V2CosignerData memory cosignerData)
        private
        pure
        returns (bytes memory sig)
    {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        sig = bytes.concat(r, s, bytes1(v));
    }

    function cosignOrder(bytes32 orderHash, CosignerData memory cosignerData) private view returns (bytes memory sig) {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        sig = bytes.concat(r, s, bytes1(v));
    }

    function cosignPriorityOrder(bytes32 orderHash, PriorityCosignerData memory cosignerData)
        private
        view
        returns (bytes memory sig)
    {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        sig = bytes.concat(r, s, bytes1(v));
    }
}

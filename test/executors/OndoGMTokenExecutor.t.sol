// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {OndoGMTokenExecutor} from "../../src/sample-executors/OndoGMTokenExecutor.sol";
import {IGMTokenManager, Quote, QuoteSide} from "../../src/external/IGMTokenManager.sol";
import {OrderInfo, SignedOrder, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";

import {
    V2DutchOrder,
    V2DutchOrderLib,
    CosignerData as V2CosignerData,
    V2DutchOrderReactor,
    DutchOutput,
    DutchInput
} from "../../src/reactors/V2DutchOrderReactor.sol";
import {
    V3DutchOrder,
    V3DutchOrderLib,
    CosignerData as V3CosignerData,
    V3DutchOrderReactor
} from "../../src/reactors/V3DutchOrderReactor.sol";
import {V3DutchInput} from "../../src/lib/V3DutchOrderLib.sol";

import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockGMTokenManager} from "../util/mock/MockGMTokenManager.sol";
import {MockUSDTApproveToken} from "../util/mock/MockUSDTApproveToken.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {CurveBuilder} from "../util/CurveBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

/// @notice Tests the OndoGMTokenExecutor JIT mint/redeem flow against both V2 and V3 Dutch reactors.
/// @dev Most tests use 18-decimal mocks. A dedicated safety test exercises a 6-decimal stablecoin path.
///      Quotes use USD price with 18 decimals, and mock manager value math is `price * quantity / 1e18`.
contract OndoGMTokenExecutorTest is Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using V2DutchOrderLib for V2DutchOrder;
    using V3DutchOrderLib for V3DutchOrder;

    uint256 constant ONE = 1e18;
    bytes32 constant EXECUTOR_USER_ID = bytes32(uint256(0xA11CE));
    address constant PROTOCOL_FEE_OWNER = address(80085);
    uint256 constant cosignerPrivateKey = 0x99999999;

    uint256 swapperPrivateKey = 0x12341235;
    uint256 attestorPrivateKey = 0xa77e57;
    address swapper = vm.addr(0x12341235);
    address attestor = vm.addr(0xa77e57);

    IPermit2 permit2;
    V2DutchOrderReactor reactorV2;
    V3DutchOrderReactor reactorV3;
    OndoGMTokenExecutor executorV2;
    OndoGMTokenExecutor executorV3;
    MockGMTokenManager gmManager;

    MockERC20 gmToken; // e.g. AAPLon
    MockERC20 stable; // e.g. USDC
    MockERC20 nonStable; // e.g. WETH (a non-stable order input)

    function setUp() public {
        vm.warp(1000);

        permit2 = IPermit2(deployPermit2());
        reactorV2 = new V2DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
        reactorV3 = new V3DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);

        gmToken = new MockERC20("Apple GM", "AAPLon", 18);
        stable = new MockERC20("USD Coin", "USDC", 18);
        nonStable = new MockERC20("Wrapped Ether", "WETH", 18);

        gmManager = new MockGMTokenManager(attestor);
        // seed manager inventory for both mint (GM out) and redeem (stable out)
        gmToken.mint(address(gmManager), 1_000_000 * ONE);
        stable.mint(address(gmManager), 1_000_000 * ONE);

        executorV2 = new OndoGMTokenExecutor(address(this), reactorV2, address(this), gmManager);
        executorV3 = new OndoGMTokenExecutor(address(this), reactorV3, address(this), gmManager);
        gmManager.setRegisteredUserId(address(executorV2), EXECUTOR_USER_ID);
        gmManager.setRegisteredUserId(address(executorV3), EXECUTOR_USER_ID);

        // swapper approves permit2 for every possible input token
        stable.forceApprove(swapper, address(permit2), type(uint256).max);
        gmToken.forceApprove(swapper, address(permit2), type(uint256).max);
        nonStable.forceApprove(swapper, address(permit2), type(uint256).max);
    }

    /* ----------------------------------- MINT (buy GM token) ----------------------------------- */

    function testMintBuyGmToken_V2() public {
        uint256 quantity = 100 * ONE; // GM tokens swapper buys
        uint256 cost = 100 * ONE; // stable swapper pays (price 1.0)

        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 1);
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), quantity);

        executorV2.execute(order, cb);

        assertEq(gmToken.balanceOf(swapper), quantity, "swapper got GM tokens");
        assertEq(stable.balanceOf(swapper), 0, "swapper spent stable");
        assertEq(stable.balanceOf(address(gmManager)), 1_000_000 * ONE + cost, "manager received deposit");
    }

    function testMintBuyGmToken_V3() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;

        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 1);
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order = _signV3(reactorV3, ERC20(address(stable)), cost, address(gmToken), quantity);

        executorV3.execute(order, cb);

        assertEq(gmToken.balanceOf(swapper), quantity, "swapper got GM tokens");
        assertEq(stable.balanceOf(swapper), 0, "swapper spent stable");
    }

    function testMintBuyGmToken_V2_DoesNotReapproveMaxForUSDTLikeOutput() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;
        address firstSwapper = swapper;

        MockUSDTApproveToken usdtLikeGmToken = new MockUSDTApproveToken("Apple GM", "AAPLon", 18);
        usdtLikeGmToken.mint(address(gmManager), 1_000_000 * ONE);
        stable.mint(firstSwapper, cost);

        _executeV2MintOrder(address(usdtLikeGmToken), cost, quantity, 1000);

        assertEq(usdtLikeGmToken.allowance(address(executorV2), address(reactorV2)), type(uint256).max);

        uint256 secondSwapperPrivateKey = 0x556677;
        address secondSwapper = vm.addr(secondSwapperPrivateKey);
        stable.forceApprove(secondSwapper, address(permit2), type(uint256).max);
        stable.mint(secondSwapper, cost);
        swapperPrivateKey = secondSwapperPrivateKey;
        swapper = secondSwapper;

        _executeV2MintOrder(address(usdtLikeGmToken), cost, quantity, 1001);

        assertEq(usdtLikeGmToken.balanceOf(firstSwapper), quantity, "first swapper got GM tokens");
        assertEq(usdtLikeGmToken.balanceOf(secondSwapper), quantity, "second swapper got GM tokens");
        assertEq(usdtLikeGmToken.allowance(address(executorV2), address(reactorV2)), type(uint256).max);
    }

    function testMintBuyGmToken_V2_6DecimalSafety() public {
        uint8 sixDecimals = 6;
        uint256 quantity = 100 * 1e6;
        uint256 cost = 100 * 1e6;

        MockERC20 gmToken6 = new MockERC20("Apple GM 6", "AAPLon6", sixDecimals);
        MockERC20 stable6 = new MockERC20("USD Coin 6", "USDC6", sixDecimals);

        gmToken6.mint(address(gmManager), 1_000_000 * 1e6);
        stable6.mint(swapper, cost);
        stable6.forceApprove(swapper, address(permit2), type(uint256).max);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken6), ONE, quantity, 1_002);
        bytes memory cb = abi.encode(
            OndoGMTokenExecutor.OndoFill({
                action: OndoGMTokenExecutor.Action.MINT,
                quote: quote,
                signature: _signQuoteWithKey(quote, attestorPrivateKey),
                stableToken: address(stable6),
                stableAmount: cost
            })
        );
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable6)), cost, address(gmToken6), quantity);

        executorV2.execute(order, cb);

        assertEq(gmToken6.balanceOf(swapper), quantity, "swapper got 6-dec GM tokens");
        assertEq(stable6.balanceOf(swapper), 0, "swapper spent 6-dec stable");
        assertEq(stable6.balanceOf(address(gmManager)), cost, "manager received 6-dec deposit");
    }

    /* --------------------------------- REDEEM (sell GM token) --------------------------------- */

    function testRedeemSellGmToken_V2() public {
        uint256 quantity = 100 * ONE; // GM tokens swapper sells
        uint256 proceeds = 100 * ONE; // stable swapper receives (price 1.0)

        gmToken.mint(swapper, quantity);

        Quote memory quote = _quote(QuoteSide.SELL, address(gmToken), ONE, quantity, 2);
        bytes memory cb = _redeemCallback(quote, proceeds);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(gmToken)), quantity, address(stable), proceeds);

        executorV2.execute(order, cb);

        assertEq(stable.balanceOf(swapper), proceeds, "swapper got stable");
        assertEq(gmToken.balanceOf(swapper), 0, "swapper sold GM tokens");
        assertEq(gmToken.balanceOf(address(gmManager)), 1_000_000 * ONE + quantity, "manager received GM tokens");
    }

    function testRedeemSellGmToken_V3() public {
        uint256 quantity = 100 * ONE;
        uint256 proceeds = 100 * ONE;

        gmToken.mint(swapper, quantity);

        Quote memory quote = _quote(QuoteSide.SELL, address(gmToken), ONE, quantity, 2);
        bytes memory cb = _redeemCallback(quote, proceeds);
        SignedOrder memory order = _signV3(reactorV3, ERC20(address(gmToken)), quantity, address(stable), proceeds);

        executorV3.execute(order, cb);

        assertEq(stable.balanceOf(swapper), proceeds, "swapper got stable");
        assertEq(gmToken.balanceOf(swapper), 0, "swapper sold GM tokens");
    }

    /* ----------------------------------- filler margin ----------------------------------- */

    /// @notice Mint more GM tokens than the order owes the swapper; residual stays in the executor
    ///         and is sweepable by the owner.
    function testFillerKeepsMargin() public {
        uint256 minted = 100 * ONE;
        uint256 owed = 99 * ONE; // swapper receives slightly less than minted
        uint256 cost = 100 * ONE;

        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, minted, 3);
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), owed);

        executorV2.execute(order, cb);

        assertEq(gmToken.balanceOf(swapper), owed, "swapper got owed amount");
        assertEq(gmToken.balanceOf(address(executorV2)), minted - owed, "executor keeps margin");

        executorV2.withdrawERC20(gmToken, address(this));
        assertEq(gmToken.balanceOf(address(this)), minted - owed, "owner swept margin");
    }

    /* --------------------------- inventory-funded mint (non-stable input) --------------------------- */

    /// @notice Option-2 funding model: the swapper pays a NON-stable input (WETH). The executor fronts
    ///         USDC from its own pre-funded inventory to mint GM, delivers GM to the swapper, and
    ///         retains the swapper's WETH as filler inventory (owner sweeps it via withdrawERC20).
    ///         No swap leg, no flash loan — just executor-held stablecoin inventory.
    function testMintFromInventory_NonStableInput_V2() public {
        uint256 quantity = 100 * ONE; // GM tokens swapper buys
        uint256 wethIn = 0.05 ether; // what the swapper pays (non-stable)
        uint256 mintCost = 100 * ONE; // USDC the executor fronts to Ondo

        nonStable.mint(swapper, wethIn);
        // pre-fund the executor's own stablecoin inventory
        stable.mint(address(executorV2), mintCost);

        // order: input = WETH (from swapper), output = GM (to swapper)
        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 10);
        bytes memory cb = _mintCallback(quote, mintCost); // deposits `stable`, not the WETH input
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(nonStable)), wethIn, address(gmToken), quantity);

        executorV2.execute(order, cb);

        assertEq(gmToken.balanceOf(swapper), quantity, "swapper got GM tokens");
        assertEq(nonStable.balanceOf(swapper), 0, "swapper paid WETH");
        assertEq(nonStable.balanceOf(address(executorV2)), wethIn, "executor retained swapper's WETH");
        assertEq(stable.balanceOf(address(executorV2)), 0, "executor's USDC inventory spent on mint");
        assertEq(stable.balanceOf(address(gmManager)), 1_000_000 * ONE + mintCost, "manager received USDC deposit");

        // owner sweeps the retained WETH out-of-band
        executorV2.withdrawERC20(nonStable, address(this));
        assertEq(nonStable.balanceOf(address(this)), wethIn, "owner swept retained WETH");
    }

    /// @notice Same inventory-funded mint as the V2 case, against the V3 (block-decay) reactor — the
    ///         executor is reactor-version-agnostic, so balance-sourcing is identical.
    function testMintFromInventory_NonStableInput_V3() public {
        uint256 quantity = 100 * ONE; // GM tokens swapper buys
        uint256 wethIn = 0.05 ether; // what the swapper pays (non-stable)
        uint256 mintCost = 100 * ONE; // USDC the executor fronts to Ondo

        nonStable.mint(swapper, wethIn);
        // pre-fund the executor's own stablecoin inventory
        stable.mint(address(executorV3), mintCost);

        // order: input = WETH (from swapper), output = GM (to swapper)
        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 11);
        bytes memory cb = _mintCallback(quote, mintCost); // deposits `stable`, not the WETH input
        SignedOrder memory order = _signV3(reactorV3, ERC20(address(nonStable)), wethIn, address(gmToken), quantity);

        executorV3.execute(order, cb);

        assertEq(gmToken.balanceOf(swapper), quantity, "swapper got GM tokens");
        assertEq(nonStable.balanceOf(swapper), 0, "swapper paid WETH");
        assertEq(nonStable.balanceOf(address(executorV3)), wethIn, "executor retained swapper's WETH");
        assertEq(stable.balanceOf(address(executorV3)), 0, "executor's USDC inventory spent on mint");
        assertEq(stable.balanceOf(address(gmManager)), 1_000_000 * ONE + mintCost, "manager received USDC deposit");

        // owner sweeps the retained WETH out-of-band
        executorV3.withdrawERC20(nonStable, address(this));
        assertEq(nonStable.balanceOf(address(this)), wethIn, "owner swept retained WETH");
    }

    /* ----------------------------------- reverts ----------------------------------- */

    function testReverts_ExpiredAttestation() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;
        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 4);
        quote.expiration = block.timestamp - 1; // expired
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), quantity);

        vm.expectRevert(MockGMTokenManager.AttestationExpired.selector);
        executorV2.execute(order, cb);
    }

    function testReverts_BadAttestor() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;
        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 5);
        // sign with the wrong key
        bytes memory badSig = _signQuoteWithKey(quote, 0xbad);
        bytes memory cb = abi.encode(
            OndoGMTokenExecutor.OndoFill({
                action: OndoGMTokenExecutor.Action.MINT,
                quote: quote,
                signature: badSig,
                stableToken: address(stable),
                stableAmount: cost
            })
        );
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), quantity);

        vm.expectRevert(MockGMTokenManager.InvalidAttestor.selector);
        executorV2.execute(order, cb);
    }

    function testReverts_ActionQuoteSideMismatchOnMint() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;
        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.SELL, address(gmToken), ONE, quantity, 6);
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), quantity);

        vm.expectRevert(OndoGMTokenExecutor.ActionQuoteSideMismatch.selector);
        executorV2.execute(order, cb);
    }

    function testReverts_ActionQuoteSideMismatchOnRedeem() public {
        uint256 quantity = 100 * ONE;
        uint256 proceeds = 100 * ONE;
        gmToken.mint(swapper, quantity);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 7);
        bytes memory cb = _redeemCallback(quote, proceeds);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(gmToken)), quantity, address(stable), proceeds);

        vm.expectRevert(OndoGMTokenExecutor.ActionQuoteSideMismatch.selector);
        executorV2.execute(order, cb);
    }

    function testReverts_MintOutputTokenMismatch() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;
        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 7_001);
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), cost, address(nonStable), quantity);

        vm.expectRevert(
            abi.encodeWithSelector(
                OndoGMTokenExecutor.OutputTokenMismatch.selector, address(gmToken), address(nonStable)
            )
        );
        executorV2.execute(order, cb);
    }

    function testReverts_MintQuoteQuantityTooLowForOrderOutput() public {
        uint256 quotedQuantity = 99 * ONE;
        uint256 requiredOutputAmount = 100 * ONE;
        uint256 cost = 99 * ONE;
        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quotedQuantity, 7_002);
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order =
            _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), requiredOutputAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                OndoGMTokenExecutor.QuoteQuantityTooLow.selector, quotedQuantity, requiredOutputAmount
            )
        );
        executorV2.execute(order, cb);
    }

    function testReverts_RedeemInputTokenMismatch() public {
        uint256 quantity = 100 * ONE;
        uint256 proceeds = 100 * ONE;
        nonStable.mint(swapper, quantity);

        Quote memory quote = _quote(QuoteSide.SELL, address(gmToken), ONE, quantity, 7_003);
        bytes memory cb = _redeemCallback(quote, proceeds);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(nonStable)), quantity, address(stable), proceeds);

        vm.expectRevert(
            abi.encodeWithSelector(
                OndoGMTokenExecutor.InputTokenMismatch.selector, address(gmToken), address(nonStable)
            )
        );
        executorV2.execute(order, cb);
    }

    function testReverts_RedeemOutputTokenMismatch() public {
        uint256 quantity = 100 * ONE;
        uint256 proceeds = 100 * ONE;
        gmToken.mint(swapper, quantity);

        Quote memory quote = _quote(QuoteSide.SELL, address(gmToken), ONE, quantity, 7_004);
        bytes memory cb = _redeemCallback(quote, proceeds);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(gmToken)), quantity, address(nonStable), proceeds);

        vm.expectRevert(
            abi.encodeWithSelector(
                OndoGMTokenExecutor.OutputTokenMismatch.selector, address(stable), address(nonStable)
            )
        );
        executorV2.execute(order, cb);
    }

    function testReverts_RedeemQuoteQuantityMismatchInputAmount() public {
        uint256 inputAmount = 100 * ONE;
        uint256 quoteQuantity = 99 * ONE;
        uint256 proceeds = 99 * ONE;
        gmToken.mint(swapper, inputAmount);

        Quote memory quote = _quote(QuoteSide.SELL, address(gmToken), ONE, quoteQuantity, 7_005);
        bytes memory cb = _redeemCallback(quote, proceeds);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(gmToken)), inputAmount, address(stable), proceeds);

        vm.expectRevert(
            abi.encodeWithSelector(OndoGMTokenExecutor.QuoteQuantityMismatch.selector, quoteQuantity, inputAmount)
        );
        executorV2.execute(order, cb);
    }

    function testReverts_MultiOutputOrderNotSupported() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;
        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 7_006);
        bytes memory cb = _mintCallback(quote, cost);
        uint256[] memory outputAmounts = new uint256[](2);
        outputAmounts[0] = 50 * ONE;
        outputAmounts[1] = 50 * ONE;
        DutchOutput[] memory outputs =
            OutputsBuilder.multipleDutch(address(gmToken), outputAmounts, outputAmounts, swapper);
        SignedOrder memory order = _signV2WithOutputs(reactorV2, ERC20(address(stable)), cost, outputs);

        vm.expectRevert(abi.encodeWithSelector(OndoGMTokenExecutor.InvalidOutputCount.selector, 2));
        executorV2.execute(order, cb);
    }

    function testReverts_QuoteChainIdMismatch() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;
        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 8);
        quote.chainId = block.chainid + 1;
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), quantity);

        vm.expectRevert(MockGMTokenManager.InvalidChainId.selector);
        executorV2.execute(order, cb);
    }

    function testReverts_UserIdMismatch() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;
        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 9);
        quote.userId = bytes32(uint256(0xBEEF));
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), quantity);

        vm.expectRevert(
            abi.encodeWithSelector(
                MockGMTokenManager.UserIdMismatch.selector, EXECUTOR_USER_ID, bytes32(uint256(0xBEEF))
            )
        );
        executorV2.execute(order, cb);
    }

    function testReverts_UserNotRegistered() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;
        stable.mint(swapper, cost);
        gmManager.setRegisteredUserId(address(executorV2), bytes32(0));

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, 10_000);
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), quantity);

        vm.expectRevert(MockGMTokenManager.UserNotRegistered.selector);
        executorV2.execute(order, cb);
    }

    function testReverts_AttestationReplay() public {
        uint256 quantity = 100 * ONE;
        uint256 cost = 100 * ONE;
        uint256 attestationId = 10_001;
        stable.mint(swapper, cost);

        Quote memory quote = _quote(QuoteSide.BUY, address(gmToken), ONE, quantity, attestationId);
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory firstOrder = _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), quantity);
        executorV2.execute(firstOrder, cb);

        address secondSwapper = _switchSwapper(0x777777);
        stable.mint(secondSwapper, cost);
        SignedOrder memory secondOrder = _signV2(reactorV2, ERC20(address(stable)), cost, address(gmToken), quantity);

        vm.expectRevert(MockGMTokenManager.AttestationAlreadyUsed.selector);
        executorV2.execute(secondOrder, cb);
    }

    function testReverts_NotWhitelistedCaller() public {
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), ONE, address(gmToken), ONE);
        vm.prank(address(0xdead));
        vm.expectRevert(OndoGMTokenExecutor.CallerNotWhitelisted.selector);
        executorV2.execute(order, bytes(""));
    }

    function testReverts_MsgSenderNotReactor() public {
        vm.prank(address(0xdead));
        vm.expectRevert(OndoGMTokenExecutor.MsgSenderNotReactor.selector);
        executorV2.reactorCallback(new ResolvedOrder[](0), bytes(""));
    }

    /* ----------------------------------- helpers ----------------------------------- */

    function _quote(QuoteSide side, address asset, uint256 price, uint256 quantity, uint256 attestationId)
        internal
        view
        returns (Quote memory)
    {
        return Quote({
            chainId: block.chainid,
            attestationId: attestationId,
            userId: EXECUTOR_USER_ID,
            asset: asset,
            price: price,
            quantity: quantity,
            expiration: block.timestamp + 1000,
            side: side,
            additionalData: bytes32(0)
        });
    }

    function _signQuoteWithKey(Quote memory quote, uint256 key) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                gmManager.QUOTE_TYPEHASH(),
                quote.chainId,
                quote.attestationId,
                quote.userId,
                quote.asset,
                quote.price,
                quote.quantity,
                quote.expiration,
                uint8(quote.side),
                quote.additionalData
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", gmManager.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return bytes.concat(r, s, bytes1(v));
    }

    function _mintCallback(Quote memory quote, uint256 depositAmount) internal view returns (bytes memory) {
        return abi.encode(
            OndoGMTokenExecutor.OndoFill({
                action: OndoGMTokenExecutor.Action.MINT,
                quote: quote,
                signature: _signQuoteWithKey(quote, attestorPrivateKey),
                stableToken: address(stable),
                stableAmount: depositAmount
            })
        );
    }

    function _executeV2MintOrder(address asset, uint256 cost, uint256 quantity, uint256 attestationId) internal {
        Quote memory quote = _quote(QuoteSide.BUY, asset, ONE, quantity, attestationId);
        bytes memory cb = _mintCallback(quote, cost);
        SignedOrder memory order = _signV2(reactorV2, ERC20(address(stable)), cost, asset, quantity);
        executorV2.execute(order, cb);
    }

    function _switchSwapper(uint256 newSwapperPrivateKey) internal returns (address newSwapper) {
        newSwapper = vm.addr(newSwapperPrivateKey);
        stable.forceApprove(newSwapper, address(permit2), type(uint256).max);
        gmToken.forceApprove(newSwapper, address(permit2), type(uint256).max);
        nonStable.forceApprove(newSwapper, address(permit2), type(uint256).max);
        swapperPrivateKey = newSwapperPrivateKey;
        swapper = newSwapper;
    }

    function _redeemCallback(Quote memory quote, uint256 minReceive) internal view returns (bytes memory) {
        return abi.encode(
            OndoGMTokenExecutor.OndoFill({
                action: OndoGMTokenExecutor.Action.REDEEM,
                quote: quote,
                signature: _signQuoteWithKey(quote, attestorPrivateKey),
                stableToken: address(stable),
                stableAmount: minReceive
            })
        );
    }

    function _signV2(
        V2DutchOrderReactor reactor,
        ERC20 inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 outputAmount
    ) internal view returns (SignedOrder memory) {
        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(inputToken, inputAmount, inputAmount),
            baseOutputs: OutputsBuilder.singleDutch(outputToken, outputAmount, outputAmount, swapper),
            cosignerData: _buildV2CosignerData(block.timestamp + 1000),
            cosignature: bytes("")
        });
        return _finalizeV2(order);
    }

    function _signV2WithOutputs(
        V2DutchOrderReactor reactor,
        ERC20 inputToken,
        uint256 inputAmount,
        DutchOutput[] memory outputs
    ) internal view returns (SignedOrder memory) {
        V2CosignerData memory cosignerData = _buildV2CosignerData(block.timestamp + 1000);
        cosignerData.outputAmounts = new uint256[](outputs.length);

        V2DutchOrder memory order = V2DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000),
            cosigner: vm.addr(cosignerPrivateKey),
            baseInput: DutchInput(inputToken, inputAmount, inputAmount),
            baseOutputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        return _finalizeV2(order);
    }

    function _buildV2CosignerData(uint256 deadline) internal view returns (V2CosignerData memory) {
        return V2CosignerData({
            decayStartTime: block.timestamp,
            decayEndTime: deadline,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: new uint256[](1)
        });
    }

    function _finalizeV2(V2DutchOrder memory order) internal view returns (SignedOrder memory) {
        bytes32 orderHash = order.hash();
        order.cosignature = _cosignV2(orderHash, order.cosignerData);
        return SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
    }

    function _signV3(
        V3DutchOrderReactor reactor,
        ERC20 inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 outputAmount
    ) internal view returns (SignedOrder memory) {
        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000),
            cosigner: vm.addr(cosignerPrivateKey),
            startingBaseFee: block.basefee,
            baseInput: V3DutchInput(inputToken, inputAmount, CurveBuilder.emptyCurve(), inputAmount, 0),
            baseOutputs: OutputsBuilder.singleV3Dutch(
                outputToken, outputAmount, outputAmount, CurveBuilder.emptyCurve(), swapper
            ),
            cosignerData: _buildV3CosignerData(),
            cosignature: bytes("")
        });
        return _finalizeV3(order);
    }

    function _buildV3CosignerData() internal view returns (V3CosignerData memory) {
        return V3CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: new uint256[](1)
        });
    }

    function _finalizeV3(V3DutchOrder memory order) internal view returns (SignedOrder memory) {
        bytes32 orderHash = order.hash();
        order.cosignature = _cosignV3(orderHash, order.cosignerData);
        return SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));
    }

    function _cosignV2(bytes32 orderHash, V2CosignerData memory cosignerData) internal pure returns (bytes memory) {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function _cosignV3(bytes32 orderHash, V3CosignerData memory cosignerData) internal view returns (bytes memory) {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }
}

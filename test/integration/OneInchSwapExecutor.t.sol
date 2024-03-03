// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {OneInchSwapExecutor} from "../../src/sample-executors/OneInchSwapExecutor.sol";
import {InputToken, OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {DutchOrderReactor, DutchOrder, DutchInput, DutchOutput} from "../../src/reactors/DutchOrderReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {IOneInchSwap} from "../../src/external/IOneInchExchange.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

// This set of tests will use a mainnet fork to test integration.
contract OneInchSwapExecutorTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using SafeTransferLib for ERC20;

    ERC20 constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address poolWethDaiV3 = 0x60594a405d53811d3BC4766596EFD80fd545A270;
    address poolWethUsdtV3 = 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;
    address poolWethDaiV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address poolWethUsdtV2 = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

    uint256 private constant _ONE_FOR_ZERO_MASK = 1 << 255;
    uint256 private constant _WETH_MASK =
        0x4000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant _REVERSE_MASK =
        0x8000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant _NUMERATOR_MASK =
        0x0000000000000000ffffffff0000000000000000000000000000000000000000;

    ERC20 constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    IOneInchSwap constant OneInchSwap =
        IOneInchSwap(0x1111111254EEB25477B68fb85Ed929f73A960582);
    address constant WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    IPermit2 constant PERMIT2 =
        IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    uint256 constant ONE = 1000000000000000000;

    address swapper;
    address swapper2;
    uint256 swapperPrivateKey;
    uint256 swapper2PrivateKey;
    address filler;
    OneInchSwapExecutor oneInchSwapExecutor;
    DutchOrderReactor dloReactor;

    function setUp() public {
        swapperPrivateKey = 0xbabe;
        swapper = vm.addr(swapperPrivateKey);
        swapper2PrivateKey = 0xbeef;
        swapper2 = vm.addr(swapper2PrivateKey);
        filler = makeAddr("filler");
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"), 19317569);
        dloReactor = new DutchOrderReactor(PERMIT2, address(0));
        oneInchSwapExecutor = new OneInchSwapExecutor(
            address(this),
            dloReactor,
            address(this),
            OneInchSwap,
            address(WETH)
        );

        // Swapper max approves permit post
        vm.prank(swapper);
        WETH.approve(address(PERMIT2), type(uint256).max);

        // Transfer 3 WETH to swapper
        vm.prank(WHALE);
        WETH.transfer(swapper, 3 * ONE);
    }

    function testSwapWethToDaiViaUniswapV3Swap() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                3000 * ONE,
                3000 * ONE,
                address(swapper)
            )
        });

        address[] memory tokensToApproveForInchSwap = new address[](1);
        tokensToApproveForInchSwap[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);
        bytes[] memory multicallData = new bytes[](1);
        uint256[] memory pools = new uint256[](1);
        pools[0] = uint256(uint160(poolWethDaiV3)) | _ONE_FOR_ZERO_MASK;
        multicallData[0] = abi.encode(true, 2 * ONE, 3000 * ONE, pools);

        oneInchSwapExecutor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(swapperPrivateKey, address(PERMIT2), order)
            ),
            abi.encode(
                tokensToApproveForInchSwap,
                tokensToApproveForReactor,
                multicallData
            )
        );

        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(DAI.balanceOf(swapper), 3000 * ONE);
        assertEq(
            DAI.balanceOf(address(oneInchSwapExecutor)),
            3434832882175252658649
        );
    }

    function testSwapWethToUSDTViaUniswapV3Swap() public {
        uint256 output = 300 * 10 ** 6;

        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(
                address(USDT),
                output,
                output,
                address(swapper)
            )
        });

        address[] memory tokensToApproveForInchSwap = new address[](1);
        tokensToApproveForInchSwap[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(USDT);
        bytes[] memory multicallData = new bytes[](1);
        uint256[] memory pools = new uint256[](1);
        pools[0] = uint256(uint160(poolWethUsdtV3));
        multicallData[0] = abi.encode(true, 2 * ONE, output, pools);

        oneInchSwapExecutor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(swapperPrivateKey, address(PERMIT2), order)
            ),
            abi.encode(
                tokensToApproveForInchSwap,
                tokensToApproveForReactor,
                multicallData
            )
        );

        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(USDT.balanceOf(swapper), output);
        assertEq(USDT.balanceOf(address(oneInchSwapExecutor)), 6123437158);
    }

    function testSwapWethToDaiViaUnoswap() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                3000 * ONE,
                3000 * ONE,
                address(swapper)
            )
        });

        address[] memory tokensToApproveForInchSwap = new address[](1);
        tokensToApproveForInchSwap[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);
        bytes[] memory multicallData = new bytes[](1);
        uint256[] memory pools = new uint256[](1);
        pools[0] =
            uint256(uint160(poolWethDaiV2)) |
            ((997 * 1e6) << 160) |
            _REVERSE_MASK;
        multicallData[0] = abi.encode(false, 2 * ONE, 3000 * ONE, pools);

        oneInchSwapExecutor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(swapperPrivateKey, address(PERMIT2), order)
            ),
            abi.encode(
                tokensToApproveForInchSwap,
                tokensToApproveForReactor,
                multicallData
            )
        );

        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(DAI.balanceOf(swapper), 3000 * ONE);
        assertEq(
            DAI.balanceOf(address(oneInchSwapExecutor)),
            3421548247069031214034
        );
    }

    function testSwapWethToUSDTViaUnoswap() public {
        uint256 output = 300 * 10 ** 6;

        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(
                address(USDT),
                output,
                output,
                address(swapper)
            )
        });

        address[] memory tokensToApproveForInchSwap = new address[](1);
        tokensToApproveForInchSwap[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(USDT);
        bytes[] memory multicallData = new bytes[](1);
        uint256[] memory pools = new uint256[](1);
        pools[0] =
            uint256(uint160(poolWethUsdtV2)) |
            ((997 * 1e6) << 160);
        multicallData[0] = abi.encode(false, 2 * ONE, output, pools);

        oneInchSwapExecutor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(swapperPrivateKey, address(PERMIT2), order)
            ),
            abi.encode(
                tokensToApproveForInchSwap,
                tokensToApproveForReactor,
                multicallData
            )
        );

        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(USDT.balanceOf(swapper), output);
        assertEq(USDT.balanceOf(address(oneInchSwapExecutor)), 6118601478);
    }

    function testSwapWethToDaiTwiceViaUnoswap() public {
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                3000 * ONE,
                3000 * ONE,
                address(swapper)
            )
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                1600 * ONE,
                1600 * ONE,
                address(swapper)
            )
        });
        address[] memory tokensToApproveForInchSwap = new address[](1);
        tokensToApproveForInchSwap[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);

        bytes[] memory multicallData = new bytes[](1);

        uint256[] memory pools = new uint256[](1);
        pools[0] =
            uint256(uint160(poolWethDaiV2)) |
            ((997 * 1e6) << 160) |
            _REVERSE_MASK;
        multicallData[0] = abi.encode(false, 2 * ONE, 3000 * ONE, pools);

        oneInchSwapExecutor.execute(
            SignedOrder(
                abi.encode(order1),
                signOrder(swapperPrivateKey, address(PERMIT2), order1)
            ),
            abi.encode(
                tokensToApproveForInchSwap,
                tokensToApproveForReactor,
                multicallData
            )
        );
        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(DAI.balanceOf(swapper), 3000 * ONE);
        assertEq(
            DAI.balanceOf(address(oneInchSwapExecutor)),
            3421548247069031214034
        );

        multicallData[0] = abi.encode(false, ONE, 1600 * ONE, pools);

        oneInchSwapExecutor.execute(
            SignedOrder(
                abi.encode(order2),
                signOrder(swapperPrivateKey, address(PERMIT2), order2)
            ),
            abi.encode(
                tokensToApproveForInchSwap,
                new address[](0),
                multicallData
            )
        );
        assertEq(WETH.balanceOf(swapper), 0);
        assertEq(DAI.balanceOf(swapper), 4600 * ONE);
        assertEq(
            DAI.balanceOf(address(oneInchSwapExecutor)),
            5028150952619573560479
        );
    }

    function testSwapWethToDaiTwiceViaUniswapV3Swap() public {
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                3000 * ONE,
                3000 * ONE,
                address(swapper)
            )
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                1600 * ONE,
                1600 * ONE,
                address(swapper)
            )
        });
        address[] memory tokensToApproveForInchSwap = new address[](1);
        tokensToApproveForInchSwap[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);

        bytes[] memory multicallData = new bytes[](1);

        uint256[] memory pools = new uint256[](1);
        pools[0] = uint256(uint160(poolWethDaiV3)) | _ONE_FOR_ZERO_MASK;
        multicallData[0] = abi.encode(true, 2 * ONE, 3000 * ONE, pools);

        oneInchSwapExecutor.execute(
            SignedOrder(
                abi.encode(order1),
                signOrder(swapperPrivateKey, address(PERMIT2), order1)
            ),
            abi.encode(
                tokensToApproveForInchSwap,
                tokensToApproveForReactor,
                multicallData
            )
        );
        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(DAI.balanceOf(swapper), 3000 * ONE);
        assertEq(
            DAI.balanceOf(address(oneInchSwapExecutor)),
            3434832882175252658649
        );

        multicallData[0] = abi.encode(true, ONE, 1600 * ONE, pools);

        oneInchSwapExecutor.execute(
            SignedOrder(
                abi.encode(order2),
                signOrder(swapperPrivateKey, address(PERMIT2), order2)
            ),
            abi.encode(new address[](0), new address[](0), multicallData)
        );
        assertEq(WETH.balanceOf(swapper), 0);
        assertEq(DAI.balanceOf(swapper), 4600 * ONE);
        assertEq(
            DAI.balanceOf(address(oneInchSwapExecutor)),
            5048706619852333457000
        );
    }

    function testSwapWethToDaiViaUnoswapInsufficientOutput() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                4000 * ONE,
                4000 * ONE,
                address(swapper)
            )
        });

        address[] memory tokensToApproveForInchSwap = new address[](1);
        tokensToApproveForInchSwap[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);
        bytes[] memory multicallData = new bytes[](1);
        uint256[] memory pools = new uint256[](1);
        pools[0] =
            uint256(uint160(poolWethDaiV2)) |
            ((997 * 1e6) << 160) |
            _REVERSE_MASK;
        multicallData[0] = abi.encode(false, 2 * ONE, 9000 * ONE, pools);

        vm.expectRevert();
        oneInchSwapExecutor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(swapperPrivateKey, address(PERMIT2), order)
            ),
            abi.encode(
                tokensToApproveForInchSwap,
                tokensToApproveForReactor,
                multicallData
            )
        );
    }

    function testSwapWethToDaiViaUniswapV3SwapInsufficientOutput() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                4000 * ONE,
                4000 * ONE,
                address(swapper)
            )
        });

        address[] memory tokensToApproveForInchSwap = new address[](1);
        tokensToApproveForInchSwap[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);

        bytes[] memory multicallData = new bytes[](1);

        uint256[] memory pools = new uint256[](1);
        pools[0] = uint256(uint160(poolWethDaiV3)) | _ONE_FOR_ZERO_MASK;
        multicallData[0] = abi.encode(true, 2 * ONE, 8000 * ONE, pools);
        vm.expectRevert();
        oneInchSwapExecutor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(swapperPrivateKey, address(PERMIT2), order)
            ),
            abi.encode(
                tokensToApproveForInchSwap,
                tokensToApproveForReactor,
                multicallData
            )
        );
    }

    function testBatchWethToDaiViaUniswapV3Swap() public {
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                3000 * ONE,
                3000 * ONE,
                address(swapper)
            )
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                3000 * ONE,
                3000 * ONE,
                address(swapper)
            )
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(
            abi.encode(order1),
            signOrder(swapperPrivateKey, address(PERMIT2), order1)
        );
        signedOrders[1] = SignedOrder(
            abi.encode(order2),
            signOrder(swapperPrivateKey, address(PERMIT2), order2)
        );

        address[] memory tokensToApproveForInchSwap = new address[](1);
        tokensToApproveForInchSwap[0] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);
        bytes[] memory multicallData = new bytes[](2);
        uint256[] memory pools = new uint256[](1);
        pools[0] = uint256(uint160(poolWethDaiV3)) | _ONE_FOR_ZERO_MASK;
        multicallData[0] = abi.encode(true, ONE, 3000 * ONE, pools);
        multicallData[1] = abi.encode(true, ONE, 3000 * ONE, pools);

        oneInchSwapExecutor.executeBatch(
            signedOrders,
            abi.encode(
                tokensToApproveForInchSwap,
                tokensToApproveForReactor,
                multicallData
            )
        );
        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(DAI.balanceOf(swapper), 2 * 3000 * ONE);
        assertEq(
            DAI.balanceOf(address(oneInchSwapExecutor)),
            434832882175252658649
        );
    }

    function testBatchWethToDaiViaUnoswap() public {
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                3000 * ONE,
                3000 * ONE,
                address(swapper)
            )
        });
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder
                .init(address(dloReactor))
                .withSwapper(swapper)
                .withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(WETH, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(
                address(DAI),
                3000 * ONE,
                3000 * ONE,
                address(swapper)
            )
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(
            abi.encode(order1),
            signOrder(swapperPrivateKey, address(PERMIT2), order1)
        );
        signedOrders[1] = SignedOrder(
            abi.encode(order2),
            signOrder(swapperPrivateKey, address(PERMIT2), order2)
        );

        address[] memory tokensToApproveForInchSwap = new address[](2);
        tokensToApproveForInchSwap[0] = address(WETH);
        tokensToApproveForInchSwap[1] = address(WETH);

        address[] memory tokensToApproveForReactor = new address[](1);
        tokensToApproveForReactor[0] = address(DAI);
        bytes[] memory multicallData = new bytes[](2);
        uint256[] memory pools = new uint256[](1);
        pools[0] =
            uint256(uint160(poolWethDaiV2)) |
            ((997 * 1e6) << 160) |
            _REVERSE_MASK;
        multicallData[0] = abi.encode(false, ONE, 3000 * ONE, pools);
        multicallData[1] = abi.encode(false, ONE, 3000 * ONE, pools);

        oneInchSwapExecutor.executeBatch(
            signedOrders,
            abi.encode(
                tokensToApproveForInchSwap,
                tokensToApproveForReactor,
                multicallData
            )
        );
        assertEq(WETH.balanceOf(swapper), ONE);
        assertEq(DAI.balanceOf(swapper), 2 * 3000 * ONE);
        assertEq(
            DAI.balanceOf(address(oneInchSwapExecutor)),
            421544071471587661367
        );
    }
}

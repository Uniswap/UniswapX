// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MultiFillerSwapRouter02Executor} from "../../src/sample-executors/MultiFillerSwapRouter02Executor.sol";
import {DutchOrderReactor, DutchOrder, DutchInput, DutchOutput} from "../../src/reactors/DutchOrderReactor.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {MockSwapRouter} from "../util/mock/MockSwapRouter.sol";
import {OutputToken, InputToken, OrderInfo, ResolvedOrder, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ISwapRouter02} from "../../src/external/ISwapRouter02.sol";
import {IUniV3SwapRouter} from "../../src/external/IUniV3SwapRouter.sol";

// This set of tests will use a mock swap router to simulate the Uniswap swap router.
contract SwapRouter02ExecutorTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;

    uint256 fillerPrivateKey;
    uint256 swapperPrivateKey;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    WETH weth;
    address filler;
    address swapper;
    MultiFillerSwapRouter02Executor swapRouter02Executor;
    MockSwapRouter mockSwapRouter;
    DutchOrderReactor reactor;
    IPermit2 permit2;

    uint256 constant ONE = 10 ** 18;
    // Represents a 0.3% fee, but setting this doesn't matter
    uint24 constant FEE = 3000;
    address constant PROTOCOL_FEE_OWNER = address(80085);

    address[] public whitelistedAddresses = [
        0xE93F29d10383C9B873e6c5218E7174F8392a740A,
        0x5763dB43549ba523A163193898E397DC840A32AE,
        0x326b39ad29df260ce36dEFC3025ae444F2d19438,
        0xe557206B5C3c98C547c222dFD189C27D079F8cc3,
        0x99eD4Eb1A2F9a43b47DcD1bf86A73BfCF170283E,
        0x9675E6d51B877AE8ADdBbFa28D2A97A56D876802,
        0x6377A5C224423beB0d8a4731dEd3d459a2387f7d,
        0x8528fe29b65f566DE5a24Ef9112a953109112ED3,
        0xa17Fbb0b5a251A7ACA3BD7377e7eCC4F700A2C09,
        0x1B483952B78Bd1E2E6b9742D0B9Da03E1eD168B6,
        0xC556337FCE1e2d108c4B0e426E623f8Bdc6405c0,
        0xc8Bb5C046F70E2DbA481c9Ad9C9Ad55ebAe54BFf,
        0xE561762D6B1d766885BF64FFc7CAc5552862B5f6,
        0xb7eBAdAC72A3dDA2F363Db26B9cDe03c539AEcA3,
        0x37BDe7E563cf2E122AdD2A8D988CafdB58F74b3E,
        0xAA59D3FCaEFDcA4d9dD2D2a34DeF79985386020B,
        0x4FB8a80b40eDE87fbf26aa5a25E8e5A07deDAEb6,
        0x27cC7F8aF1E799eD75aeB9C2756C6dcC3A495b39,
        0x19F456E396970Ef5FDE1bd755c884659211d4367,
        0xD504decb1DB1C0cBe01B498E6F690B0dA49B100a,
        0x56A69b3B0f24F27eDF3b5dF2b0a28D00B7ED973d,
        0x28B5f87500177987B65696bcB703eC74a186215f,
        0x1971c4e485c86FD3369d211A1539bAf741DD4066,
        0x69CFcfDB3784f8d9D1fc13C4152f2Fc42FCD5695,
        0xdC55523bc4b116E0817270d62F19ec3540e24Db8,
        0xb9054004164cf211f452dF931078d067CcD71Dff,
        0xeab74725990e0cF3aF9bD1A4c5449CeAdd8c96FB,
        0x2bd908Bd30B384fdfD4Ef63A9996fdc1e1B465b9,
        0x6f29211688B565E6d9fC34c0bCbAfFc912761a44,
        0x05cb5Ed3176F2FAd4acfE727a4DA233A5cb436f4,
        0x6257ccE851c33820bB0B853f0Cb2aDAEc7E47Fbd,
        0xebb6A4c602AF711A113d76eDe3d6Af3c8035D08d,
        0x1Fe954Cd85938a6915A0E9A331708F912011c2b7,
        0x9e48dA4e289F1357a74a5897efB7edE2B19C02cb,
        0x3b86b9236811aAba0d895a1DF34e6e32E16D5373,
        0xC0b2a431E4023f2C8874a59c21e5A7d5563Dcd7e,
        0xb8C76fb91CB32870ee594804bA976BEAc4ecfdAC,
        0xE8056A65017166BCD6ae0Df5D092BbDeB22419F6,
        0x176D2753B5fE481132784a25A88870e79BE4F897,
        0x008dC7B274FEE2184373AFf5B3A188B4d162dd78,
        0x229638ce60e39A5cCE80d68476E473ca9Eb529cD,
        0xdbD2ce742cf75b73FaAa94170537eB520ceDEBE8,
        0xd725Bf68220194141Bda3A1aebfe673Aa9b84d3D,
        0x4ea6b06e5139F3483A7A9a17988f6854c914Ab61,
        0x5357d7E2ebb125b43d3aD8500004f927aC0D8a56,
        0xbc9a6DF348e2E661921848B2efa9316813C8989b,
        0x19f11950e4d57ADae785aEdBb84D651f1581BC1b,
        0x7e346652905a7e5A0b3275817E016eB9f0A58d72,
        0x80147F235A2400F3a5CA7ddCFbd89D9ea5b70f0d,
        0x5317c87A39b113a72168b3382e4c4650a4f4EB82
    ];
    mapping(address => bool) public isWhitelistedCaller;

    // to test sweeping ETH
    receive() external payable {}

    function setUp() public {
        vm.warp(1000);

        // Mock input/output tokens
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        weth = new WETH();

        // Mock filler and swapper
        fillerPrivateKey = 0x12341234;
        filler = vm.addr(fillerPrivateKey);
        swapperPrivateKey = 0x12341235;
        swapper = vm.addr(swapperPrivateKey);

        // Instantiate relevant contracts
        mockSwapRouter = new MockSwapRouter(address(weth));
        permit2 = IPermit2(deployPermit2());
        reactor = new DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
        swapRouter02Executor =
            new MultiFillerSwapRouter02Executor(reactor, address(this), ISwapRouter02(address(mockSwapRouter)));

        // Do appropriate max approvals
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);
        for (uint256 i = 0; i < whitelistedAddresses.length; i++) {
            isWhitelistedCaller[whitelistedAddresses[i]] = true;
        }
    }

    function testReactorCallback() public {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        outputs[0].recipient = swapper;
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);
        bytes memory fillData = abi.encode(tokensToApproveForSwapRouter02, multicallData);

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            InputToken(tokenIn, ONE, ONE),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );
        tokenIn.mint(address(swapRouter02Executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        vm.prank(address(reactor));
        swapRouter02Executor.reactorCallback(resolvedOrders, whitelistedAddresses[0], fillData);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), ONE);
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), 0);
        assertEq(tokenOut.balanceOf(address(swapper)), ONE);
    }

    // Output will resolve to 0.5. Input = 1. SwapRouter exchanges at 1 to 1 rate.
    // There will be 0.5 output token remaining in SwapRouter02Executor.
    function testExecute() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
        });

        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        vm.prank(whitelistedAddresses[0]);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenIn.balanceOf(address(swapRouter02Executor)), 0);
        assertEq(tokenOut.balanceOf(swapper), ONE / 2);
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), ONE / 2);
    }

    // Output will resolve to 0.5. Input = 1. SwapRouter exchanges at 1 to 1 rate.
    // There will be 0.5 output token remaining in SwapRouter02Executor.
    function testExecuteAllWhitelisted() public {
        for (uint256 i = 0; i < whitelistedAddresses.length; i++) {
            DutchOrder memory order = DutchOrder({
                info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                    .withNonce(i),
                decayStartTime: block.timestamp - 100,
                decayEndTime: block.timestamp + 100,
                input: DutchInput(tokenIn, ONE, ONE),
                outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
            });

            tokenIn.mint(swapper, ONE);
            tokenOut.mint(address(mockSwapRouter), ONE);

            address[] memory tokensToApproveForSwapRouter02 = new address[](1);
            tokensToApproveForSwapRouter02[0] = address(tokenIn);

            bytes[] memory multicallData = new bytes[](1);
            IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
                path: abi.encodePacked(tokenIn, FEE, tokenOut),
                recipient: address(swapRouter02Executor),
                amountIn: ONE,
                amountOutMinimum: 0
            });
            multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

            vm.prank(whitelistedAddresses[i]);
            reactor.execute(
                SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
                swapRouter02Executor,
                abi.encode(tokensToApproveForSwapRouter02, multicallData)
            );
        }
    }

    // Requested output = 2 & input = 1. SwapRouter swaps at 1 to 1 rate, so there will
    // there will be an overflow error when reactor tries to transfer 2 outputToken out of fill contract.
    function testExecuteInsufficientOutput() public {
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            // The output will resolve to 2
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE * 2, ONE * 2, address(swapper))
        });

        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE * 2);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        vm.expectRevert("TRANSFER_FAILED");
        vm.prank(whitelistedAddresses[0]);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
    }

    // Two orders, first one has input = 1 and outputs = [1]. Second one has input = 3
    // and outputs = [2]. Mint swapper 10 input and mint mockSwapRouter 10 output. After
    // the execution, swapper should have 6 input / 3 output, mockSwapRouter should have
    // 4 input / 6 output, and swapRouter02Executor should have 0 input / 1 output.
    function testExecuteBatch() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 10);
        tokenOut.mint(address(mockSwapRouter), outputAmount * 10);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, swapper)
        });
        bytes memory sig1 = signOrder(swapperPrivateKey, address(permit2), order1);
        signedOrders[0] = SignedOrder(abi.encode(order1), sig1);

        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, inputAmount * 3, inputAmount * 3),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, swapper)
        });
        bytes memory sig2 = signOrder(swapperPrivateKey, address(permit2), order2);
        signedOrders[1] = SignedOrder(abi.encode(order2), sig2);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: inputAmount * 4,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        vm.prank(whitelistedAddresses[0]);
        reactor.executeBatch(
            signedOrders, swapRouter02Executor, abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
        assertEq(tokenOut.balanceOf(swapper), 3 ether);
        assertEq(tokenIn.balanceOf(swapper), 6 ether);
        assertEq(tokenOut.balanceOf(address(mockSwapRouter)), 6 ether);
        assertEq(tokenIn.balanceOf(address(mockSwapRouter)), 4 ether);
        assertEq(tokenOut.balanceOf(address(swapRouter02Executor)), 10 ** 18);
        assertEq(tokenIn.balanceOf(address(swapRouter02Executor)), 0);
    }

    function testNotWhitelistedCaller(address caller) public {
        vm.assume(!isWhitelistedCaller[caller]);
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp - 100,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE, 0, address(swapper))
        });

        tokenIn.mint(swapper, ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);

        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);

        vm.prank(caller);
        vm.expectRevert(MultiFillerSwapRouter02Executor.CallerNotWhitelisted.selector);
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order)),
            swapRouter02Executor,
            abi.encode(tokensToApproveForSwapRouter02, multicallData)
        );
    }

    // Very similar to `testReactorCallback`, but do not vm.prank the reactor when calling `reactorCallback`, so reverts
    // in
    function testMsgSenderNotReactor() public {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        address[] memory tokensToApproveForSwapRouter02 = new address[](1);
        tokensToApproveForSwapRouter02[0] = address(tokenIn);

        bytes[] memory multicallData = new bytes[](1);
        IUniV3SwapRouter.ExactInputParams memory exactInputParams = IUniV3SwapRouter.ExactInputParams({
            path: abi.encodePacked(tokenIn, FEE, tokenOut),
            recipient: address(swapRouter02Executor),
            amountIn: ONE,
            amountOutMinimum: 0
        });
        multicallData[0] = abi.encodeWithSelector(IUniV3SwapRouter.exactInput.selector, exactInputParams);
        bytes memory fillData = abi.encode(tokensToApproveForSwapRouter02, multicallData);

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        bytes memory sig = hex"1234";
        resolvedOrders[0] = ResolvedOrder(
            OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            InputToken(tokenIn, ONE, ONE),
            outputs,
            sig,
            keccak256(abi.encode(1))
        );
        tokenIn.mint(address(swapRouter02Executor), ONE);
        tokenOut.mint(address(mockSwapRouter), ONE);
        vm.expectRevert(MultiFillerSwapRouter02Executor.MsgSenderNotReactor.selector);
        swapRouter02Executor.reactorCallback(resolvedOrders, address(this), fillData);
    }

    function testUnwrapWETH() public {
        vm.deal(address(weth), 1 ether);
        deal(address(weth), address(swapRouter02Executor), ONE);
        uint256 balanceBefore = address(this).balance;
        swapRouter02Executor.unwrapWETH(address(this));
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function testUnwrapWETHNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xbeef));
        swapRouter02Executor.unwrapWETH(address(this));
    }

    function testWithdrawETH() public {
        vm.deal(address(swapRouter02Executor), 1 ether);
        uint256 balanceBefore = address(this).balance;
        swapRouter02Executor.withdrawETH(address(this));
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function testWithdrawETHNotOwner() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xbeef));
        swapRouter02Executor.withdrawETH(address(this));
    }
}

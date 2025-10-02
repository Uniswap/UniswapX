// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../../../util/DeployPermit2.sol";
import {DCAHookHarness} from "./DCAHookHarness.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";
import {DCAIntent, OutputAllocation, PrivateIntent} from "../../../../src/v4/hooks/dca/DCAStructs.sol";
import {InputToken, OutputToken} from "../../../../src/base/ReactorStructs.sol";
import {ResolvedOrder, OrderInfo} from "../../../../src/v4/base/ReactorStructs.sol";
import {IPreExecutionHook, IPostExecutionHook} from "../../../../src/v4/interfaces/IHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IDCAHook} from "../../../../src/v4/interfaces/IDCAHook.sol";
import {IAuctionResolver} from "../../../../src/v4/interfaces/IAuctionResolver.sol";

contract DCAHook_validateStaticFieldsTest is Test, DeployPermit2 {
    DCAHookHarness hook;
    IPermit2 permit2;
    address constant REACTOR_ADDRESS = address(0x2345);
    IReactor constant REACTOR = IReactor(REACTOR_ADDRESS);

    address constant SWAPPER = address(0x1234);
    address constant COSIGNER = address(0x5678);
    address constant RECIPIENT_1 = address(0x9ABC);
    address constant RECIPIENT_2 = address(0x4455);

    ERC20 constant INPUT_TOKEN = ERC20(address(0xAAAA));
    ERC20 constant OUTPUT_TOKEN = ERC20(address(0xBBBB));
    ERC20 constant WRONG_INPUT_TOKEN = ERC20(address(0xCCCC));
    ERC20 constant WRONG_OUTPUT_TOKEN = ERC20(address(0xDDDD));

    uint256 constant CHAIN_ID = 1;
    uint256 constant WRONG_CHAIN_ID = 137;
    uint256 constant NONCE = 42;

    function setUp() public {
        permit2 = IPermit2(deployPermit2());
        hook = new DCAHookHarness(permit2, REACTOR);
        vm.chainId(CHAIN_ID);
    }

    function _createIntent(
        address hookAddress,
        uint256 chainId,
        address swapper,
        address inputToken,
        address outputToken
    ) internal view returns (DCAIntent memory) {
        OutputAllocation[] memory allocations = new OutputAllocation[](1);
        allocations[0] = OutputAllocation({recipient: RECIPIENT_1, basisPoints: 10000});

        PrivateIntent memory privateIntent = PrivateIntent({
            totalAmount: 1000e18,
            exactFrequency: 3600,
            numChunks: 10,
            salt: bytes32(0),
            oracleFeeds: new bytes32[](0)
        });

        return DCAIntent({
            swapper: swapper,
            nonce: NONCE,
            chainId: chainId,
            hookAddress: hookAddress,
            isExactIn: true,
            inputToken: inputToken,
            outputToken: outputToken,
            cosigner: COSIGNER,
            minPeriod: 300,
            maxPeriod: 7200,
            minChunkSize: 1e18,
            maxChunkSize: 100e18,
            minPrice: 0,
            deadline: block.timestamp + 1 days,
            outputAllocations: allocations,
            privateIntent: privateIntent
        });
    }

    function _createResolvedOrder(address swapper, ERC20 inputToken, ERC20 outputToken, uint256 outputCount)
        internal
        view
        returns (ResolvedOrder memory)
    {
        OutputToken[] memory outputs = new OutputToken[](outputCount);
        for (uint256 i = 0; i < outputCount; i++) {
            outputs[i] = OutputToken({token: address(outputToken), amount: 100e18, recipient: RECIPIENT_1});
        }

        return ResolvedOrder({
            info: OrderInfo({
                reactor: IReactor(REACTOR_ADDRESS),
                swapper: swapper,
                nonce: NONCE,
                deadline: block.timestamp + 1 days,
                preExecutionHook: IPreExecutionHook(address(0)),
                preExecutionHookData: "",
                postExecutionHook: IPostExecutionHook(address(0)),
                postExecutionHookData: "",
                auctionResolver: IAuctionResolver(address(0))
            }),
            input: InputToken({token: inputToken, amount: 10e18, maxAmount: 10e18}),
            outputs: outputs,
            sig: "",
            hash: bytes32(0),
            auctionResolver: address(0)
        });
    }

    function test_validateStaticFields_success() public view {
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 1);

        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_success_multipleOutputs() public view {
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 3);

        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_revert_wrongHook() public {
        address wrongHook = address(0xEEEE);
        DCAIntent memory intent =
            _createIntent(wrongHook, CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.WrongHook.selector, wrongHook, address(hook)));
        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_revert_wrongChain() public {
        DCAIntent memory intent =
            _createIntent(address(hook), WRONG_CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.WrongChain.selector, WRONG_CHAIN_ID, CHAIN_ID));
        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_revert_swapperMismatch() public {
        address wrongSwapper = address(0xFFFF);
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(wrongSwapper, INPUT_TOKEN, OUTPUT_TOKEN, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.SwapperMismatch.selector, wrongSwapper, SWAPPER));
        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_revert_wrongInputToken() public {
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, WRONG_INPUT_TOKEN, OUTPUT_TOKEN, 1);

        vm.expectRevert(
            abi.encodeWithSelector(IDCAHook.WrongInputToken.selector, address(WRONG_INPUT_TOKEN), address(INPUT_TOKEN))
        );
        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_revert_wrongOutputToken_singleOutput() public {
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, WRONG_OUTPUT_TOKEN, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDCAHook.WrongOutputToken.selector, address(WRONG_OUTPUT_TOKEN), address(OUTPUT_TOKEN)
            )
        );
        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_revert_wrongOutputToken_multipleOutputs() public {
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 3);

        order.outputs[1].token = address(WRONG_OUTPUT_TOKEN);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDCAHook.WrongOutputToken.selector, address(WRONG_OUTPUT_TOKEN), address(OUTPUT_TOKEN)
            )
        );
        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_revert_wrongOutputToken_lastOutput() public {
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 5);

        order.outputs[4].token = address(WRONG_OUTPUT_TOKEN);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDCAHook.WrongOutputToken.selector, address(WRONG_OUTPUT_TOKEN), address(OUTPUT_TOKEN)
            )
        );
        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_revert_emptyOutputs() public view {
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 0);

        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_orderOfValidation() public {
        DCAIntent memory intent = _createIntent(
            address(0xBAD), WRONG_CHAIN_ID, address(0x9999), address(WRONG_INPUT_TOKEN), address(WRONG_OUTPUT_TOKEN)
        );

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.WrongHook.selector, address(0xBAD), address(hook)));
        hook.validateStaticFields(intent, order);
    }

    function testFuzz_validateStaticFields_differentAddresses(
        address fuzzHook,
        address fuzzSwapper,
        address fuzzInputToken,
        address fuzzOutputToken
    ) public {
        vm.assume(fuzzHook != address(0));
        vm.assume(fuzzSwapper != address(0));
        vm.assume(fuzzInputToken != address(0));
        vm.assume(fuzzOutputToken != address(0));
        vm.assume(fuzzHook != address(hook));

        DCAIntent memory intent = _createIntent(fuzzHook, CHAIN_ID, fuzzSwapper, fuzzInputToken, fuzzOutputToken);

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.WrongHook.selector, fuzzHook, address(hook)));
        hook.validateStaticFields(intent, order);
    }

    function testFuzz_validateStaticFields_differentChainIds(uint256 fuzzChainId) public {
        vm.assume(fuzzChainId != CHAIN_ID);
        vm.assume(fuzzChainId > 0 && fuzzChainId < type(uint256).max);

        DCAIntent memory intent =
            _createIntent(address(hook), fuzzChainId, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.WrongChain.selector, fuzzChainId, CHAIN_ID));
        hook.validateStaticFields(intent, order);
    }

    function testFuzz_validateStaticFields_multipleOutputs(uint8 outputCount) public view {
        vm.assume(outputCount > 0 && outputCount <= 10);

        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, outputCount);

        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_gasOptimization_multipleOutputs() public view {
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 20);

        uint256 gasBefore = gasleft();
        hook.validateStaticFields(intent, order);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 50000, "Gas usage should be reasonable for 20 outputs");
    }

    function test_validateStaticFields_allFieldsWrong() public {
        DCAIntent memory intent = _createIntent(
            address(0xBAD), WRONG_CHAIN_ID, address(0x8888), address(WRONG_INPUT_TOKEN), address(WRONG_OUTPUT_TOKEN)
        );

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, OUTPUT_TOKEN, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.WrongHook.selector, address(0xBAD), address(hook)));
        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_zeroAddressInputToken() public view {
        DCAIntent memory intent = _createIntent(address(hook), CHAIN_ID, SWAPPER, address(0), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, ERC20(address(0)), OUTPUT_TOKEN, 1);

        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_zeroAddressOutputToken() public view {
        DCAIntent memory intent = _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(0));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, ERC20(address(0)), 1);

        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_zeroAddressSwapper() public view {
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, address(0), address(INPUT_TOKEN), address(OUTPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(address(0), INPUT_TOKEN, OUTPUT_TOKEN, 1);

        hook.validateStaticFields(intent, order);
    }

    function test_validateStaticFields_identicalInputOutputTokens() public view {
        DCAIntent memory intent =
            _createIntent(address(hook), CHAIN_ID, SWAPPER, address(INPUT_TOKEN), address(INPUT_TOKEN));

        ResolvedOrder memory order = _createResolvedOrder(SWAPPER, INPUT_TOKEN, INPUT_TOKEN, 1);

        hook.validateStaticFields(intent, order);
    }
}

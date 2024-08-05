// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {
    PriorityOrderReactorDeployment, DeployPriorityOrderReactor
} from "../../script/DeployPriorityOrderReactor.s.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {OrderInfo, InputToken, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {PriorityOrderReactor} from "../../src/reactors/PriorityOrderReactor.sol";
import {PriorityOrder, PriorityInput, PriorityOutput, PriorityCosignerData} from "../../src/lib/PriorityOrderLib.sol";
import {MockERC20} from "../../test/util/mock/MockERC20.sol";

contract DeployPriorityOrderReactorTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    DeployPriorityOrderReactor deployer;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        deployer = new DeployPriorityOrderReactor();
        tokenIn = new MockERC20{salt: 0x00}("Token A", "TA", 18);
        tokenOut = new MockERC20{salt: 0x00}("Token B", "TB", 18);
    }

    function testDeploy() public {
        vm.setEnv("FOUNDRY_REACTOR_OWNER", "0x0000000000000000000000000000000000000000");
        PriorityOrderReactorDeployment memory deployment = deployer.run();

        assertEq(address(deployment.reactor.permit2()), address(deployment.permit2));
        quoteTest(deployment);
    }

    // running this against the deployment since it's a pretty good end-to-end test
    // ensuring all of the contracts are properly set up and integrated with each other
    function quoteTest(PriorityOrderReactorDeployment memory deployment) public {
        uint256 swapperPrivateKey = 0x12341234;
        address swapper = vm.addr(swapperPrivateKey);

        tokenIn.mint(address(swapper), ONE);
        tokenIn.forceApprove(swapper, address(deployment.permit2), ONE);
        PriorityOutput[] memory priorityOutputs = new PriorityOutput[](1);
        priorityOutputs[0] = PriorityOutput(address(tokenOut), ONE, 1, address(0));
        PriorityOrder memory order = PriorityOrder({
            info: OrderInfoBuilder.init(address(deployment.reactor)).withSwapper(address(swapper)),
            cosigner: address(0),
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: ONE, mpsPerPriorityFeeWei: 0}),
            outputs: priorityOutputs,
            cosignerData: PriorityCosignerData({auctionTargetBlock: block.number}),
            cosignature: bytes("")
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(deployment.permit2), order);
        ResolvedOrder memory quote = deployment.quoter.quote(abi.encode(order), sig);

        assertEq(address(quote.input.token), address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }
}

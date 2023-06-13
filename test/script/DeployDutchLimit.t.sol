// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DutchDeployment, DeployDutch} from "../../script/DeployDutch.s.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {OrderInfo, InputToken, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {DutchOrder, DutchOutput, DutchInput} from "../../src/reactors/DutchOrderReactor.sol";

contract DeployDutchTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    DeployDutch deployer;
    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        deployer = new DeployDutch();
    }

    function testDeploy() public {
        DutchDeployment memory deployment = deployer.run();

        assertEq(address(deployment.reactor.permit2()), address(deployment.permit2));
        quoteTest(deployment);
    }

    // running this against the deployment since it's a pretty good end-to-end test
    // ensuring all of the contracts are properly set up and integrated with each other
    function quoteTest(DutchDeployment memory deployment) public {
        uint256 swapperPrivateKey = 0x12341234;
        address swapper = vm.addr(swapperPrivateKey);

        deployment.tokenIn.mint(address(swapper), ONE);
        deployment.tokenIn.forceApprove(swapper, address(deployment.permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(deployment.tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(deployment.reactor)).withSwapper(address(swapper)),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(deployment.tokenIn, ONE, ONE),
            outputs: dutchOutputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(deployment.permit2), order);
        ResolvedOrder memory quote = deployment.quoter.quote(abi.encode(order), sig);

        assertEq(address(quote.input.token), address(deployment.tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(deployment.tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {DutchLimitDeployment, DeployDutchLimit} from "../../script/DeployDutchLimit.s.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {Signature, SigType} from "permitpost/interfaces/IPermitPost.sol";
import {OrderInfo, InputToken, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {DutchLimitOrder, DutchOutput} from "../../src/reactors/dutch-limit/DutchLimitOrderStructs.sol";

contract DeployDutchLimitTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    DeployDutchLimit deployer;
    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        deployer = new DeployDutchLimit();
    }

    function testDeploy() public {
        DutchLimitDeployment memory deployment = deployer.run();

        assertEq(address(deployment.reactor.permitPost()), address(deployment.permitPost));
        quoteTest(deployment);
    }

    // running this against the deployment since it's a pretty good end-to-end test
    // ensuring all of the contracts are properly set up and integrated with each other
    function quoteTest(DutchLimitDeployment memory deployment) public {
        uint256 makerPrivateKey = 0x12341234;
        address maker = vm.addr(makerPrivateKey);

        deployment.tokenIn.mint(address(maker), ONE);
        deployment.tokenIn.forceApprove(maker, address(deployment.permitPost), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(deployment.tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(deployment.reactor)).withOfferer(address(maker)),
            startTime: block.timestamp,
            input: InputToken(address(deployment.tokenIn), ONE),
            outputs: dutchOutputs
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        Signature memory sig =
            signOrder(vm, makerPrivateKey, address(deployment.permitPost), order.info, order.input, orderHash);
        ResolvedOrder memory quote = deployment.quoter.quote(abi.encode(order), sig);

        assertEq(quote.input.token, address(deployment.tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(deployment.tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }
}

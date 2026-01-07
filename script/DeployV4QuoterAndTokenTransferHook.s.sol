pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {OrderQuoter} from "../src/v4/lens/OrderQuoter.sol";
import {TokenTransferHook} from "../src/v4/hooks/TokenTransferHook.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IReactor} from "../src/v4/interfaces/IReactor.sol";

struct V4OrderQuoterDeployment {
    OrderQuoter quoter;
    TokenTransferHook tokenTransferHook;
}

contract DeployV4QuoterAndTokenTransferHook is Script {
    // Permit2 is deployed at the same address on all chains
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {}

    function run() public returns (V4OrderQuoterDeployment memory deployment) {
        // Read reactor address from environment: FOUNDRY_V4_REACTOR
        address reactor = vm.envAddress("FOUNDRY_V4_REACTOR");

        vm.startBroadcast();

        OrderQuoter quoter = new OrderQuoter{salt: 0x00}();
        console2.log("V4 OrderQuoter", address(quoter));

        TokenTransferHook tokenTransferHook = new TokenTransferHook{salt: 0x00}(IPermit2(PERMIT2), IReactor(reactor));
        console2.log("TokenTransferHook", address(tokenTransferHook));

        vm.stopBroadcast();

        return V4OrderQuoterDeployment(quoter, tokenTransferHook);
    }
}

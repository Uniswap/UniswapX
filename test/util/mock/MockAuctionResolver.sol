// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IAuctionResolver} from "../../../src/interfaces/IAuctionResolver.sol";
import {ResolvedOrderV2, SignedOrder} from "../../../src/base/ReactorStructs.sol";
import {MockOrder, MockOrderLib} from "./MockOrderLib.sol";

/// @notice Simple auction resolver for testing UnifiedReactor basic functionality
contract MockAuctionResolver is IAuctionResolver {
    using MockOrderLib for MockOrder;

    /// @inheritdoc IAuctionResolver
    function resolve(SignedOrder calldata signedOrder) external view override returns (ResolvedOrderV2 memory) {
        MockOrder memory mockOrder = abi.decode(signedOrder.order, (MockOrder));

        return ResolvedOrderV2({
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

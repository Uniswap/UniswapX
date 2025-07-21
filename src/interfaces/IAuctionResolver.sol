// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";

/// @notice Interface for auction mechanism resolvers
interface IAuctionResolver {
    /// @notice Resolves a signed order into a resolved order based on auction rules
    /// @param signedOrder The signed order with auction-specific order data (resolver address already stripped)
    /// @return resolvedOrder The resolved order with final amounts
    function resolve(SignedOrder calldata signedOrder) external view returns (ResolvedOrder memory resolvedOrder);

    /// @notice Get the auction type identifier
    /// @return auctionType The auction type string
    function auctionType() external pure returns (string memory);

    /// @notice Get the Permit2 order type string for EIP-712 signature verification
    /// @return orderType The EIP-712 order type string for this resolver's orders
    function getPermit2OrderType() external pure returns (string memory);
}
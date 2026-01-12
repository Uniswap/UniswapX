// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Quoter contract for v4 orders
/// @dev Note this is meant to be used as an off-chain lens contract to pre-validate generic orders
contract OrderQuoterV4 is IReactorCallback {
    /// @notice thrown if reactorCallback receives more than one order
    error OrdersLengthIncorrect();

    uint256 private constant RESOLVED_ORDER_MIN_LENGTH = 768;

    /// @notice Quote the given order, returning the ResolvedOrder object which defines
    /// the current input and output token amounts required to satisfy it
    /// Also bubbles up any reverts that would occur during the processing of the order
    /// @param reactor The v4 reactor address to use for quoting
    /// @param order abi-encoded order, including `auctionResolver` as the first encoded struct member
    /// @param sig The order signature
    /// @return result The ResolvedOrder
    function quote(IReactor reactor, bytes memory order, bytes memory sig)
        external
        returns (ResolvedOrder memory result)
    {
        try reactor.executeWithCallback(SignedOrder(order, sig), bytes("")) {}
        catch (bytes memory reason) {
            result = parseRevertReason(reason);
        }
    }

    /// @notice Return the auction resolver address from a given order (abi-encoded bytes)
    /// @param order abi-encoded order with auctionResolver as the first field
    /// @return auctionResolver The auction resolver address
    function getAuctionResolver(bytes memory order) public pure returns (address auctionResolver) {
        // In v4, orders are encoded as: abi.encode(auctionResolver, orderData)
        // The first 32 bytes after the length prefix contain the auctionResolver address
        assembly {
            // Skip the 32-byte length prefix, read the first 32 bytes (address is right-padded)
            auctionResolver := mload(add(order, 32))
        }
    }

    /// @notice Parse the revert reason into a ResolvedOrder
    /// @param reason The revert reason bytes
    /// @return The decoded ResolvedOrder
    function parseRevertReason(bytes memory reason) private pure returns (ResolvedOrder memory) {
        if (reason.length < RESOLVED_ORDER_MIN_LENGTH) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (ResolvedOrder));
        }
    }

    /// @notice Reactor callback function
    /// @dev Reverts with the resolved order as reason
    /// @param resolvedOrders The resolved orders
    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, bytes calldata) external pure {
        if (resolvedOrders.length != 1) {
            revert OrdersLengthIncorrect();
        }
        bytes memory order = abi.encode(resolvedOrders[0]);
        assembly {
            revert(add(32, order), mload(order))
        }
    }

    /// @notice Fallback function to receive ETH
    /// @dev Required for ERC20ETH transfers which send ETH to this contract
    receive() external payable {}
}


// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice Helper contract to call MixedRouteQuoterV1 and decode the return data
contract MockMixedRouteQuoterV1Wrapper {
    address private immutable quoter;

    constructor(address _quoter) {
        quoter = _quoter;
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        // quoteExactInput(bytes memory path, uint256 amountIn)
        if (msg.sig != 0xcdca1753) {
            revert("Invalid function call");
        }

        (bool success, bytes memory returnData) = address(quoter).call(data);
        if (!success) {
            revert("Failed to call quoter");
        }

        (uint256 amountOut,,,) = abi.decode(returnData, (uint256, uint160[], uint32[], uint256));
        return abi.encode(amountOut);
    }
}

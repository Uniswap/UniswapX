// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice helper library for verifying cosignatures
contract CosignerLib {
    /// @notice thrown when an order's cosignature does not match the expected cosigner
    error InvalidCosignature();

    /// @notice verify that a cosignature is valid for a given cosigner and data
    /// @param cosigner the address of the cosigner
    /// @param data the digest of (orderHash || cosignerData)
    /// @param cosignature the cosigner's signature over the data
    function verify(address cosigner, bytes32 data, bytes memory cosignature) public pure {
        (bytes32 r, bytes32 s) = abi.decode(cosignature, (bytes32, bytes32));
        uint8 v = uint8(cosignature[64]);
        address signer = ecrecover(data, v, r, s);
        if (cosigner != signer || signer == address(0)) {
            revert InvalidCosignature();
        }
    }
}

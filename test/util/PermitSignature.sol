// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Vm} from "forge-std/Vm.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/draft-EIP712.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Signature, Permit, IPermitPost} from "permitpost/interfaces/IPermitPost.sol";
import {PermitPost} from "permitpost/PermitPost.sol";

contract PermitSignature {
    bytes32 public constant _PERMIT_TYPEHASH = keccak256(
        "Permit(uint8 sigType,address token,address spender,uint256 maxAmount,uint256 deadline,uint256 nonce)"
    );
    bytes32 public constant NAME_HASH = keccak256("PermitPost");
    bytes32 public constant VERSION_HASH = keccak256("1");
    bytes32 public constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function getPermitSignature(
        Vm vm,
        uint256 privateKey,
        address post,
        Permit memory permit,
        uint8 sigType,
        uint256 nonce
    )
        internal
        returns (Signature memory sig)
    {
        bytes32 msgHash = ECDSA.toTypedDataHash(
            _domainSeparatorV4(post),
            keccak256(
                abi.encode(
                    _PERMIT_TYPEHASH, sigType, permit.token, permit.spender, permit.maxAmount, permit.deadline, nonce
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        sig = Signature(v, r, s);
    }

    function _domainSeparatorV4(address post) internal view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, NAME_HASH, VERSION_HASH, block.chainid, post));
    }
}

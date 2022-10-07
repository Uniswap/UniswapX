// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Vm} from "forge-std/Vm.sol";
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/draft-EIP712.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Signature, Permit, IPermitPost, SigType, TokenDetails, TokenType} from "permitpost/interfaces/IPermitPost.sol";
import {PermitPost} from "permitpost/PermitPost.sol";
import {OrderInfo, InputToken} from "../../src/base/ReactorStructs.sol";

contract PermitSignature {
    bytes32 public constant _PERMIT_TYPEHASH = keccak256(
        "Permit(uint8 sigType,TokenDetails[] tokens,address spender,uint256 deadline,bytes32 witness,uint256 nonce)TokenDetails(uint8 tokenType,address token,uint256 maxAmount,uint256 id)"
    );
    bytes32 public constant _TOKEN_DETAILS_TYPEHASH =
        keccak256("TokenDetails(uint8 tokenType,address token,uint256 maxAmount,uint256 id)");
    bytes32 public constant NAME_HASH = keccak256("PermitPost");
    bytes32 public constant VERSION_HASH = keccak256("1");
    bytes32 public constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function getPermitSignature(
        Vm vm,
        uint256 privateKey,
        address post,
        Permit memory permit,
        SigType sigType,
        uint256 nonce
    ) internal returns (Signature memory sig) {
        bytes32[] memory tokenHashes = new bytes32[](permit.tokens.length);
        for (uint256 i = 0; i < permit.tokens.length; ++i) {
            tokenHashes[i] = keccak256(abi.encode(_TOKEN_DETAILS_TYPEHASH, permit.tokens[i]));
        }
        bytes32 msgHash = ECDSA.toTypedDataHash(
            _domainSeparatorV4(post),
            keccak256(
                abi.encode(
                    _PERMIT_TYPEHASH,
                    sigType,
                    keccak256(abi.encodePacked(tokenHashes)),
                    permit.spender,
                    permit.deadline,
                    permit.witness,
                    nonce
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        sig = Signature(v, r, s);
    }

    function signOrder(
        Vm vm,
        uint256 privateKey,
        address post,
        OrderInfo memory info,
        InputToken memory input,
        bytes32 orderHash
    ) internal returns (Signature memory sig) {
        TokenDetails[] memory tokens = new TokenDetails[](1);
        tokens[0] = TokenDetails({tokenType: TokenType.ERC20, token: input.token, maxAmount: input.amount, id: 0});
        Permit memory permit =
            Permit({tokens: tokens, spender: info.reactor, deadline: info.deadline, witness: orderHash});
        return getPermitSignature(vm, privateKey, post, permit, SigType.UNORDERED, info.nonce);
    }

    function _domainSeparatorV4(address post) internal view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, NAME_HASH, VERSION_HASH, block.chainid, post));
    }
}

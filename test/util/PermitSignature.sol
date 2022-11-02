// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {EIP712} from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {Permit2} from "permit2/Permit2.sol";
import {LimitOrder, LimitOrderLib} from "../../src/lib/LimitOrderLib.sol";
import {DutchLimitOrder, DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {OrderInfo, InputToken} from "../../src/base/ReactorStructs.sol";

contract PermitSignature is Test {
    using LimitOrderLib for LimitOrder;
    using DutchLimitOrderLib for DutchLimitOrder;

    bytes32 public constant NAME_HASH = keccak256("Permit2");
    bytes32 public constant TYPE_HASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    string constant TYPEHASH_STUB =
        "PermitWitnessTransferFrom(address token,address spender,uint256 signedAmount,uint256 nonce,uint256 deadline,";
    bytes32 constant LIMIT_ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(TYPEHASH_STUB, "LimitOrder", " witness)", LimitOrderLib.ORDER_TYPE));

    bytes32 constant DUTCH_LIMIT_ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(TYPEHASH_STUB, "DutchLimitOrder", " witness)", DutchLimitOrderLib.ORDER_TYPE));

    function getPermitSignature(
        uint256 privateKey,
        address permit2,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes32 typeHash,
        bytes32 witness
    ) internal returns (bytes memory sig) {
        bytes32 msgHash = ECDSA.toTypedDataHash(
            _domainSeparatorV4(permit2),
            keccak256(
                abi.encode(
                    typeHash, permit.token, permit.spender, permit.signedAmount, permit.nonce, permit.deadline, witness
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        sig = bytes.concat(r, s, bytes1(v));
    }

    function signOrder(
        uint256 privateKey,
        address permit2,
        OrderInfo memory info,
        address inputToken,
        uint256 inputAmount,
        bytes32 typeHash,
        bytes32 orderHash
    ) internal returns (bytes memory sig) {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            token: inputToken,
            spender: info.reactor,
            signedAmount: inputAmount,
            nonce: info.nonce,
            deadline: info.deadline
        });
        return getPermitSignature(privateKey, permit2, permit, typeHash, orderHash);
    }

    function signOrder(uint256 privateKey, address permit2, LimitOrder memory order)
        internal
        returns (bytes memory sig)
    {
        return signOrder(
            privateKey, permit2, order.info, order.input.token, order.input.amount, LIMIT_ORDER_TYPE_HASH, order.hash()
        );
    }

    function signOrder(uint256 privateKey, address permit2, DutchLimitOrder memory order)
        internal
        returns (bytes memory sig)
    {
        return signOrder(
            privateKey,
            permit2,
            order.info,
            order.input.token,
            order.input.endAmount,
            DUTCH_LIMIT_ORDER_TYPE_HASH,
            order.hash()
        );
    }

    function _domainSeparatorV4(address permit2) internal view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, NAME_HASH, block.chainid, permit2));
    }
}

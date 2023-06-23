// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EIP712} from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {LimitOrder, LimitOrderLib} from "../../src/lib/LimitOrderLib.sol";
import {DutchOrder, DutchOrderLib} from "../../src/lib/DutchOrderLib.sol";
import {ExclusiveDutchOrder, ExclusiveDutchOrderLib} from "../../src/lib/ExclusiveDutchOrderLib.sol";
import {OrderInfo, InputToken} from "../../src/base/ReactorStructs.sol";

contract PermitSignature is Test {
    using LimitOrderLib for LimitOrder;
    using DutchOrderLib for DutchOrder;
    using ExclusiveDutchOrderLib for ExclusiveDutchOrder;

    bytes32 public constant NAME_HASH = keccak256("Permit2");
    bytes32 public constant TYPE_HASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    string constant TYPEHASH_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";
    bytes32 constant LIMIT_ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(TYPEHASH_STUB, LimitOrderLib.PERMIT2_ORDER_TYPE));

    bytes32 constant DUTCH_LIMIT_ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(TYPEHASH_STUB, DutchOrderLib.PERMIT2_ORDER_TYPE));

    bytes32 constant EXCLUSIVE_DUTCH_LIMIT_ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(TYPEHASH_STUB, ExclusiveDutchOrderLib.PERMIT2_ORDER_TYPE));

    function getPermitSignature(
        uint256 privateKey,
        address permit2,
        ISignatureTransfer.PermitTransferFrom memory permit,
        address spender,
        bytes32 typeHash,
        bytes32 witness
    ) internal view returns (bytes memory sig) {
        bytes32 msgHash = ECDSA.toTypedDataHash(
            _domainSeparatorV4(permit2),
            keccak256(
                abi.encode(
                    typeHash, _hashTokenPermissions(permit.permitted), spender, permit.nonce, permit.deadline, witness
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
    ) internal view returns (bytes memory sig) {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: inputToken, amount: inputAmount}),
            nonce: info.nonce,
            deadline: info.deadline
        });
        return getPermitSignature(privateKey, permit2, permit, address(info.reactor), typeHash, orderHash);
    }

    function signOrder(uint256 privateKey, address permit2, LimitOrder memory order)
        internal
        view
        returns (bytes memory sig)
    {
        return signOrder(
            privateKey,
            permit2,
            order.info,
            address(order.input.token),
            order.input.amount,
            LIMIT_ORDER_TYPE_HASH,
            order.hash()
        );
    }

    function signOrder(uint256 privateKey, address permit2, DutchOrder memory order)
        internal
        view
        returns (bytes memory sig)
    {
        return signOrder(
            privateKey,
            permit2,
            order.info,
            address(order.input.token),
            order.input.endAmount,
            DUTCH_LIMIT_ORDER_TYPE_HASH,
            order.hash()
        );
    }

    function signOrder(uint256 privateKey, address permit2, ExclusiveDutchOrder memory order)
        internal
        view
        returns (bytes memory sig)
    {
        return signOrder(
            privateKey,
            permit2,
            order.info,
            address(order.input.token),
            order.input.endAmount,
            EXCLUSIVE_DUTCH_LIMIT_ORDER_TYPE_HASH,
            order.hash()
        );
    }

    function _domainSeparatorV4(address permit2) internal view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, NAME_HASH, block.chainid, permit2));
    }

    function _hashTokenPermissions(ISignatureTransfer.TokenPermissions memory permitted)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permitted));
    }
}

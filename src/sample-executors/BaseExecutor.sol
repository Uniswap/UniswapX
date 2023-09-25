// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {Multicall} from "./Multicall.sol";

struct PermitData {
    address token;
    bytes data;
}

abstract contract BaseExecutor is IReactorCallback, Multicall, Owned {
    IReactor public immutable reactor;

    constructor(IReactor _reactor, address _owner) Owned(_owner) {
        reactor = _reactor;
    }

    /// @inheritdoc IReactorCallback
    function reactorCallback(ResolvedOrder[] calldata, bytes calldata callbackData) external virtual;

    function execute(SignedOrder memory order, bytes memory callbackData) public payable virtual {
        reactor.executeWithCallback{value: msg.value}(order, callbackData);
    }

    function executeBatch(SignedOrder[] memory orders, bytes memory callbackData) public payable virtual {
        reactor.executeBatchWithCallback{value: msg.value}(orders, callbackData);
    }

    /// @notice execute a signed 2612-style permit
    /// the transaction will revert if the permit cannot be executed
    function permit(PermitData memory permitData) public {
        (address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(permitData.data, (address, address, uint256, uint256, uint8, bytes32, bytes32));
        ERC20(permitData.token).permit(owner, spender, value, deadline, v, r, s);
    }

    /// @notice execute a batch of signed 2612-style permits
    /// the transaction will revert if any of the permits cannot be executed
    function permitBatch(PermitData[] memory permitData) external {
        for (uint256 i = 0; i < permitData.length;) {
            permit(permitData[i]);
            unchecked {
                i++;
            }
        }
    }

    receive() external payable {}
}

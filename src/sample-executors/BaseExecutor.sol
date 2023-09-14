// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";

library Commands {
    bytes1 internal constant COMMAND_TYPE_MASK = 0x0f;

    uint256 constant EXECUTE = 0x00;
    uint256 constant EXECUTE_BATCH = 0x01;
    uint256 constant PERMIT = 0x02;
    uint256 constant PERMIT_BATCH = 0x03;
    // 0x04 - 0x0f are reserved for future use
}

struct PermitData {
    address token;
    bytes data;
}

abstract contract BaseExecutor is IReactorCallback, Owned {
    /// @notice Thrown when attempting to execute commands and an incorrect number of inputs are provided
    error LengthMismatch();
    error InvalidCommandType(uint256 commandType);

    IReactor public immutable reactor;

    constructor(IReactor _reactor, address _owner) Owned(_owner) {
        reactor = _reactor;
    }

    function reactorCallback(ResolvedOrder[] calldata, bytes calldata callbackData) external virtual;

    function _restrictCall() internal virtual {}

    function dispatch(bytes calldata commands, bytes[] calldata inputs) external payable {
        _restrictCall();
        uint256 numCommands = commands.length;
        if (inputs.length != numCommands) revert LengthMismatch();

        // loop through all given commands, execute them and pass along outputs as defined
        for (uint256 commandIndex = 0; commandIndex < numCommands;) {
            uint256 command = uint8(commands[commandIndex] & Commands.COMMAND_TYPE_MASK);
            bytes calldata input = inputs[commandIndex];

            if (command == Commands.EXECUTE) {
                SignedOrder memory order;
                bytes memory callbackData;

                (order.order, order.sig, callbackData) = abi.decode(input, (bytes, bytes, bytes));
                _execute(order, callbackData);
            } else if (command == Commands.EXECUTE_BATCH) {
                (bytes[] memory orderInputs, bytes memory callbackData) = abi.decode(input, (bytes[], bytes));
                SignedOrder[] memory orders = new SignedOrder[](orderInputs.length);
                for (uint256 i = 0; i < orderInputs.length; i++) {
                    SignedOrder memory order;
                    (order.order, order.sig) = abi.decode(orderInputs[i], (bytes, bytes));
                    orders[i] = order;
                }

                _executeBatch(orders, callbackData);
            } else if (command == Commands.PERMIT) {
                PermitData memory permit = abi.decode(input, (PermitData));
                _permit(permit);
            } else if (command == Commands.PERMIT_BATCH) {
                PermitData[] memory permits = abi.decode(input, (PermitData[]));
                _permitBatch(permits);
            } else {
                revert InvalidCommandType(command);
            }
            unchecked {
                commandIndex++;
            }
        }
    }

    function _execute(SignedOrder memory order, bytes memory callbackData) internal {
        reactor.executeWithCallback(order, callbackData);
    }

    function _executeBatch(SignedOrder[] memory orders, bytes memory callbackData) internal {
        reactor.executeBatchWithCallback(orders, callbackData);
    }

    /// @notice execute a signed 2612-style permit
    /// the transaction will revert if the permit cannot be executed
    /// must be called before the call to the reactor
    function _permit(PermitData memory permit) internal {
        (address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(permit.data, (address, address, uint256, uint256, uint8, bytes32, bytes32));
        ERC20(permit.token).permit(owner, spender, value, deadline, v, r, s);
    }

    function _permitBatch(PermitData[] memory permits) internal {
        for (uint256 i = 0; i < permits.length;) {
            _permit(permits[i]);
            unchecked {
                i++;
            }
        }
    }

    receive() external payable {}
}

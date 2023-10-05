// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {Multicall} from "./Multicall.sol";

abstract contract BaseExecutor is IReactorCallback, Multicall, Owned {
    IReactor public immutable reactor;

    /// @notice thrown if reactorCallback is called by an address other than the reactor
    error MsgSenderNotReactor();
    error NotImplemented();

    constructor(IReactor _reactor, address _owner) Owned(_owner) {
        reactor = _reactor;
    }

    modifier onlyReactor() {
        if (msg.sender != address(reactor)) {
            revert MsgSenderNotReactor();
        }
        _;
    }

    /// @inheritdoc IReactorCallback
    /// @dev any overriding function MUST use the onlyReactor modifier
    function reactorCallback(ResolvedOrder[] calldata, bytes calldata) external virtual onlyReactor {}

    /// @notice execute a signed order
    /// @dev consider restricting who can call this function
    function execute(SignedOrder memory order, bytes memory callbackData) public payable virtual;

    /// @notice execute a batch of signed orders
    /// @dev consider restricting who can call this function
    function executeBatch(SignedOrder[] memory orders, bytes memory callbackData) public payable virtual;

    /// @notice required to receive native outputs
    receive() external payable {}
}

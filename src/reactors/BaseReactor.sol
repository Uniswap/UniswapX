// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ReactorEvents} from "../base/ReactorEvents.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {IPSFees} from "../base/IPSFees.sol";
import {SignedOrder, ResolvedOrder, OrderInfo, InputToken, OutputToken, ETH_ADDRESS} from "../base/ReactorStructs.sol";

/// @notice Generic reactor logic for settling off-chain signed orders
///     using arbitrary fill methods specified by a taker
abstract contract BaseReactor is IReactor, ReactorEvents, IPSFees, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using ResolvedOrderLib for ResolvedOrder;

    // Occurs when an output = ETH and the reactor lacks enough ETH OR output recipient cannot receive ETH
    error EtherSendFail();
    // Occurs when an output = ETH and the reactor does contain enough ETH but either 1) the direct taker did not include
    // enough ETH in their call to execute/executeBatch or 2) the fillContract did not send enough ETH to the reactor
    error InsufficientEth();

    address public immutable permit2;
    address internal constant DIRECT_TAKER_FILL = address(1);

    constructor(address _permit2, uint256 _protocolFeeBps, address _protocolFeeRecipient)
        IPSFees(_protocolFeeBps, _protocolFeeRecipient)
    {
        permit2 = _permit2;
    }

    receive() external payable {}

    /// @inheritdoc IReactor
    function execute(SignedOrder calldata order, address fillContract, bytes calldata fillData)
        external
        payable
        override
        nonReentrant
    {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = resolve(order);

        _fill(resolvedOrders, fillContract, fillData);
    }

    /// @inheritdoc IReactor
    function executeBatch(SignedOrder[] calldata orders, address fillContract, bytes calldata fillData)
        external
        payable
        override
        nonReentrant
    {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](orders.length);

        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                resolvedOrders[i] = resolve(orders[i]);
            }
        }
        _fill(resolvedOrders, fillContract, fillData);
    }

    /// @notice validates and fills a list of orders, marking it as filled
    function _fill(ResolvedOrder[] memory orders, address fillContract, bytes calldata fillData) internal {
        bool directTaker = fillContract == DIRECT_TAKER_FILL;
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedOrder memory order = orders[i];
                _takeFees(order);
                order.validate(msg.sender);
                transferInputTokens(order, directTaker ? msg.sender : fillContract);
            }
        }
        // `ethBalanceBeforeReactorCallback` and `ethGainedFromReactorCallback` are only used in non direct taker +
        // ETH output scenario
        uint256 ethBalanceBeforeReactorCallback = address(this).balance;
        if (!directTaker) {
            IReactorCallback(fillContract).reactorCallback(orders, msg.sender, fillData);
        }
        uint256 ethGainedFromReactorCallback = address(this).balance - ethBalanceBeforeReactorCallback;
        unchecked {
            // `msgValue` is only used in directTaker + ETH output scenario
            uint256 msgValue = msg.value;
            // transfer output tokens to their respective recipients
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedOrder memory resolvedOrder = orders[i];
                for (uint256 j = 0; j < resolvedOrder.outputs.length; j++) {
                    OutputToken memory output = resolvedOrder.outputs[j];

                    if (output.token == ETH_ADDRESS) {
                        (bool sent,) = output.recipient.call{value: output.amount}("");
                        if (!sent) {
                            revert EtherSendFail();
                        }
                        if (directTaker) {
                            if (msgValue >= output.amount) {
                                msgValue -= output.amount;
                            } else {
                                revert InsufficientEth();
                            }
                        } else {
                            if (ethGainedFromReactorCallback >= output.amount) {
                                ethGainedFromReactorCallback -= output.amount;
                            } else {
                                revert InsufficientEth();
                            }
                        }
                    } else {
                        if (directTaker) {
                            IAllowanceTransfer(permit2).transferFrom(
                                msg.sender, output.recipient, SafeCast.toUint160(output.amount), output.token
                            );
                        } else {
                            ERC20(output.token).safeTransferFrom(fillContract, output.recipient, output.amount);
                        }
                    }
                }
                emit Fill(orders[i].hash, msg.sender, resolvedOrder.info.offerer, resolvedOrder.info.nonce);
            }
        }
    }

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(SignedOrder calldata order) internal view virtual returns (ResolvedOrder memory resolvedOrder);

    /// @notice Transfers tokens to the fillContract
    /// @param order The encoded order to transfer tokens for
    /// @param to The address to transfer tokens to
    function transferInputTokens(ResolvedOrder memory order, address to) internal virtual;
}

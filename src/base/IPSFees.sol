// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Handling for interface-protocol-split fees
abstract contract IPSFees {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    error InvalidFee();
    error UnauthorizedFeeRecipient();

    /// @dev The number of basis points per whole
    uint256 private constant BPS = 10000;

    /// @dev The fee recipient used in feesOwed for protocol fees
    address private constant PROTOCOL_FEE_RECIPIENT_STORED = address(0);

    /// @dev The amount of fees to take in basis points
    uint256 public immutable PROTOCOL_FEE_BPS;

    /// @notice stores the owed fees
    /// @dev maps token address to owner address to amount
    mapping(address => mapping(address => uint256)) public feesOwed;

    /// @dev The address who can receive fees
    address public protocolFeeRecipient;

    modifier onlyProtocolFeeRecipient() {
        if (msg.sender != protocolFeeRecipient) revert UnauthorizedFeeRecipient();
        _;
    }

    constructor(uint256 _protocolFeeBps, address _protocolFeeRecipient) {
        if (_protocolFeeBps > BPS) revert InvalidFee();

        PROTOCOL_FEE_BPS = _protocolFeeBps;
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    /// @notice Takes fees from the order
    /// @dev modifies the fee output recipient to be this contract
    /// @dev stores state to allow fee recipients to claim later
    /// @dev Note: the fee output is defined as the last output in the order
    /// @param order The encoded order to take fees from
    function _takeFees(ResolvedOrder memory order) internal {
        // no fee output, nothing to do
        if (order.outputs.length < 2) return;

        OutputToken memory feeOutput = order.outputs[order.outputs.length - 1];
        uint256 protocolFeeAmount = feeOutput.amount.mulDivDown(PROTOCOL_FEE_BPS, BPS);

        // protocol fees are accrued to PROTOCOL_FEE_RECIPIENT_STORED as sentinel for
        // whatever address is currently set for protocolFeeRecipient
        feesOwed[feeOutput.token][PROTOCOL_FEE_RECIPIENT_STORED] += protocolFeeAmount;
        // rest goes to the original interface fee recipient
        feesOwed[feeOutput.token][feeOutput.recipient] += feeOutput.amount - protocolFeeAmount;

        // TODO: consider / bench just adding protocol fee output to the order
        //  and having filler send directly to both recipients
        // we custody the fee and they can claim later
        feeOutput.recipient = address(this);
    }

    /// @notice claim accrued fees
    /// @param token The token to claim fees for
    function claimFees(address token) external {
        address feeRecipient = msg.sender == protocolFeeRecipient ? PROTOCOL_FEE_RECIPIENT_STORED : msg.sender;
        uint256 amount = feesOwed[token][feeRecipient];
        feesOwed[token][feeRecipient] = 0;
        ERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @notice sets the protocol fee recipient
    /// @dev only callable by the current protocol fee recipient
    /// @param _protocolFeeRecipient the new fee recipient
    function setProtocolFeeRecipient(address _protocolFeeRecipient) external onlyProtocolFeeRecipient {
        protocolFeeRecipient = _protocolFeeRecipient;
    }
}

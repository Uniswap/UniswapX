// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ResolvedOrder, OutputToken, ETH_ADDRESS} from "../base/ReactorStructs.sol";

/// @notice Handling for interface-protocol-split fees
abstract contract IPSFees {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    error InvalidFee();
    error NoClaimableFees();
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
        uint256 orderOutputsLength = order.outputs.length;
        for (uint256 i = 0; i < orderOutputsLength;) {
            OutputToken memory output = order.outputs[i];

            if (output.isFeeOutput) {
                uint256 protocolFeeAmount = output.amount.mulDivDown(PROTOCOL_FEE_BPS, BPS);
                uint256 interfaceFeeAmount;
                unchecked {
                    interfaceFeeAmount = output.amount - protocolFeeAmount;
                }

                // protocol fees are accrued to PROTOCOL_FEE_RECIPIENT_STORED as sentinel for
                // whatever address is currently set for protocolFeeRecipient
                feesOwed[output.token][PROTOCOL_FEE_RECIPIENT_STORED] += protocolFeeAmount;
                // rest goes to the original interface fee recipient
                feesOwed[output.token][output.recipient] += interfaceFeeAmount;

                // we custody the fee and they can claim later
                output.recipient = address(this);
            }

            unchecked {
                i++;
            }
        }
    }

    /// @notice claim accrued fees
    /// @param token The token to claim fees for
    function claimFees(address token) external {
        address feeRecipient = msg.sender == protocolFeeRecipient ? PROTOCOL_FEE_RECIPIENT_STORED : msg.sender;
        uint256 amount = feesOwed[token][feeRecipient];
        if (amount <= 1) revert NoClaimableFees();

        feesOwed[token][feeRecipient] = 1;
        unchecked {
            if (token == ETH_ADDRESS) {
                (bool sent,) = msg.sender.call{value: amount - 1}("");
                require(sent, "Failed to send ether");
            }
            ERC20(token).safeTransfer(msg.sender, amount - 1);
        }
    }

    /// @notice sets the protocol fee recipient
    /// @dev only callable by the current protocol fee recipient
    /// @param _protocolFeeRecipient the new fee recipient
    function setProtocolFeeRecipient(address _protocolFeeRecipient) external onlyProtocolFeeRecipient {
        protocolFeeRecipient = _protocolFeeRecipient;
    }
}

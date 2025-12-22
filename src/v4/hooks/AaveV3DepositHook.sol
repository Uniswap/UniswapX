// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPostExecutionHook} from "../interfaces/IHook.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {OutputToken} from "../../base/ReactorStructs.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {CurrencyLibrary} from "../../lib/CurrencyLibrary.sol";

/// @notice Aave V3 Pool interface for supply operations
/// @dev Official interface from aave/aave-v3-core
interface IPool {
    /// @notice Supplies an `amount` of underlying asset into the reserve, receiving in return overlying aTokens
    /// @dev Pool contract must have allowance to spend funds on behalf of msg.sender
    /// @param asset The address of the underlying asset to supply
    /// @param amount The amount to be supplied
    /// @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user wants to receive them on his own wallet
    /// @param referralCode Code used to register the integrator originating the operation, for potential rewards (0 if referral program is inactive)
    /// @dev Emits a `Supply` event
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    /// @notice Emitted on supply
    /// @param reserve The address of the underlying asset of the reserve
    /// @param user The address initiating the supply
    /// @param onBehalfOf The beneficiary of the supply
    /// @param amount The amount supplied
    /// @param referralCode The referral code used
    event Supply(
        address indexed reserve, address user, address indexed onBehalfOf, uint256 amount, uint16 indexed referralCode
    );
}

/// @notice Post-execution hook that deposits output tokens into Aave V3 on behalf of swapper
/// @dev Usage pattern:
///      1. Swapper creates order with output.recipient = address(this hook)
///      2. Reactor transfers output tokens to this hook during fill
///      3. This hook approves Aave Pool and deposits tokens
///      4. Swapper receives aTokens representing their Aave deposit
/// @dev This hook only processes outputs where recipient == address(this)
///      Other outputs are ignored, allowing mixed recipient configurations
contract AaveV3DepositHook is IPostExecutionHook {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    /// @notice Aave V3 Pool contract for deposits
    IPool public immutable aavePool;

    /// @notice Thrown when attempting to deposit native ETH (not supported by Aave V3 Pool)
    /// @dev Native tokens require WETHGateway wrapper contract
    error NativeTokenNotSupported();

    /// @notice Emitted when tokens are deposited to Aave on behalf of a swapper
    /// @param swapper The address receiving the aTokens
    /// @param asset The underlying asset supplied
    /// @param amount The amount supplied
    event AaveDepositExecuted(address indexed swapper, address indexed asset, uint256 amount);

    /// @param _aavePool The Aave V3 Pool contract address
    constructor(IPool _aavePool) {
        aavePool = _aavePool;
    }

    /// @inheritdoc IPostExecutionHook
    /// @dev Deposits output tokens into Aave V3 on behalf of the swapper
    /// @dev Only processes outputs where recipient == address(this)
    /// @dev Filler parameter is unused as we only care about swapper
    function postExecutionHook(
        address,
        /* filler */
        ResolvedOrder calldata resolvedOrder
    )
        external
        override
    {
        address swapper = resolvedOrder.info.swapper;
        OutputToken[] calldata outputs = resolvedOrder.outputs;

        uint256 outputsLength = outputs.length;
        unchecked {
            for (uint256 i = 0; i < outputsLength; i++) {
                OutputToken calldata output = outputs[i];

                // Only process outputs sent to this hook
                if (output.recipient != address(this)) {
                    continue;
                }

                // Revert if native token - would need WETHGateway wrapper
                if (output.token.isNative()) {
                    revert NativeTokenNotSupported();
                }

                // Approve Aave pool to spend output tokens
                // Using SafeTransferLib for safe approval
                ERC20(output.token).safeApprove(address(aavePool), output.amount);

                // Supply tokens to Aave V3
                // onBehalfOf = swapper, so they receive the aTokens
                // referralCode = 0 (referral program currently inactive)
                aavePool.supply(
                    output.token,
                    output.amount,
                    swapper, // swapper receives aTokens
                    0 // referralCode
                );

                emit AaveDepositExecuted(swapper, output.token, output.amount);
            }
        }
    }
}

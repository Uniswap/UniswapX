// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISettlementFiller} from "../interfaces/ISettlementFiller.sol";
import {OutputToken} from "../base/SettlementStructs.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";
import {ICrossDomainMessenger} from "../external/ICrossDomainMessenger.sol";
import {ISettlementOracle} from "../interfaces/ISettlementOracle.sol";

/// @notice A cross-chain filler that could exists on mainnet for an optimism to mainnet swap settle.
/// @notice Contains logic for filling an order on mainnet and sending the settlement information to the message bridge.
contract L1SettlementFiller is ISettlementFiller {
    using SafeTransferLib for ERC20;

    ICrossDomainMessenger public immutable MESSENGER;
    ISettlementOracle public immutable ORACLE;

    constructor(address l1CrossDomainMessenger, address l2Oracle) {
        MESSENGER = ICrossDomainMessenger(l1CrossDomainMessenger);
        ORACLE = ISettlementOracle(l2Oracle);
    }

    /// @notice Thrown when output token does not match the chain id of this deployed contract
    /// @param chainId The invalid chainID
    error InvalidChainId(uint256 chainId);

    function fillAndTransmitSettlementOutputs(bytes32 orderId, OutputToken[] calldata outputs) external {
        unchecked {
            for (uint256 i = 0; i < outputs.length; i++) {
                OutputToken memory output = outputs[i];
                if (output.chainId != block.chainid) revert InvalidChainId(output.chainId);
                ERC20(output.token).safeTransferFrom(msg.sender, output.recipient, output.amount);
            }
            transmitSettlementOutputs(orderId, msg.sender, outputs);
        }
    }

    function transmitSettlementOutputs(bytes32 orderId, address filler, OutputToken[] calldata outputs) internal {
        MESSENGER.sendMessage(
            address(ORACLE),
            abi.encodeWithSelector(ISettlementOracle.logSettlementFillInfo.selector, orderId, filler, outputs),
            // not sure about the gas calculations
            uint32(gasleft())
        );
    }
}

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

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    bytes4 internal constant ERC2612_PERMIT_SIGNATURE = 0xd505accf;
    bytes4 internal constant DAI_PERMIT_SIGNATURE = 0x8fcbaf0c;

    constructor(IReactor _reactor, address _owner) Owned(_owner) {
        reactor = _reactor;
    }

    /// @inheritdoc IReactorCallback
    function reactorCallback(ResolvedOrder[] calldata, bytes calldata callbackData) external virtual;

    function execute(SignedOrder memory order, bytes memory callbackData) public payable virtual {
        reactor.executeWithCallback(order, callbackData);
    }

    function executeBatch(SignedOrder[] memory orders, bytes memory callbackData) public payable virtual {
        reactor.executeBatchWithCallback(orders, callbackData);
    }

    /// @notice execute a signed ERC2612 permit
    /// @dev since DAI has a non standard permit, it's special cased
    /// the transaction will revert if the permit cannot be executed
    function permit(PermitData memory permitData) public {
        if(permitData.token == DAI) {
            (bool success,) = permitData.token.call(abi.encodeWithSelector(DAI_PERMIT_SIGNATURE, permitData.data));
            require(success, "DAI permit failed");
        }
        else {
            (bool success,) = permitData.token.call(abi.encodeWithSelector(ERC2612_PERMIT_SIGNATURE, permitData.data);
            require(success, "ERC2612 permit failed");
        }
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

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {BaseExecutor} from "./BaseExecutor.sol";
import {Permit2Lib} from "permit2/src/libraries/Permit2Lib.sol";

struct PermitData {
    ERC20 token;
    address owner;
    address spender;
    uint256 amount;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

abstract contract BaseExecutorWithPermit is BaseExecutor {
    constructor(IReactor _reactor, address _owner) BaseExecutor(_reactor, _owner) {}

    /// @notice execute a signed ERC2612 permit
    /// the transaction will revert if the permit cannot be executed
    function permit(PermitData memory data) public {
        Permit2Lib.permit2(data.token, data.owner, data.spender, data.amount, data.deadline, data.v, data.r, data.s);
    }

    /// @notice execute a batch of signed 2612-style permits
    /// the transaction will revert if any of the permits cannot be executed
    function permitBatch(PermitData[] memory data) external {
        uint256 length = data.length;
        for (uint256 i = 0; i < length;) {
            permit(data[i]);
            unchecked {
                i++;
            }
        }
    }
}

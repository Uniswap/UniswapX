// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ArrayBuilder} from "./ArrayBuilder.sol";
import {toUint256} from "../../src/types/Uint16Array.sol";
import {NonlinearDutchDecay} from "../../src/lib/V3DutchOrderLib.sol";

library CurveBuilder {
    function emptyCurve() internal pure returns (NonlinearDutchDecay memory) {
        return NonlinearDutchDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(0, 0)), relativeAmounts: ArrayBuilder.fillInt(0, 0)
        });
    }

    function singlePointCurve(uint16 relativeBlock, int256 relativeAmount)
        internal
        pure
        returns (NonlinearDutchDecay memory)
    {
        return NonlinearDutchDecay({
            relativeBlocks: toUint256(ArrayBuilder.fillUint16(1, relativeBlock)),
            relativeAmounts: ArrayBuilder.fillInt(1, relativeAmount)
        });
    }

    function multiPointCurve(uint16[] memory relativeBlocks, int256[] memory relativeAmounts)
        internal
        pure
        returns (NonlinearDutchDecay memory)
    {
        return NonlinearDutchDecay({relativeBlocks: toUint256(relativeBlocks), relativeAmounts: relativeAmounts});
    }
}

import {Test} from "forge-std/Test.sol";
import {NonlinearDutchDecay, V3DutchOrderLib, V3DutchOutput} from "../../src/lib/V3DutchOrderLib.sol";

contract EIP712Test is Test {
    function test_NonlinearDutchDecayHash() public pure {
        assertEq(
            V3DutchOrderLib.NON_LINEAR_DECAY_TYPE_HASH,
            hex"30c39ae6ecb284279579f99803ba5d7b54275a8a6a04180056b5031b8c19a01a"
        );

        int256[] memory amounts = new int256[](1);
        amounts[0] = 1;
        NonlinearDutchDecay memory curve = NonlinearDutchDecay(1, amounts);
        assertEq(V3DutchOrderLib.hash(curve), hex"ad28931e960b684a49cdf1aca21bd966df5bac39996c5a0615c0a54f2f22a06f");
    }

    function test_V3DutchInputHash() public pure {
        assertEq(
            V3DutchOrderLib.V3_DUTCH_INPUT_TYPE_HASH,
            hex"2cc4ccc271072d8b406616a16a6e9a3935dea10f0eb920f44737e1855ecc68eb"
        );
    }

    function test_V3DutchOutputHash() public pure {
        assertEq(
            V3DutchOrderLib.V3_DUTCH_OUTPUT_TYPE_HASH,
            hex"7fd857ffad1736e72f90e17c9d15cabe562b86b45c6e618ae0e7fa92c4a6fde9"
        );

        address token = address(0);
        uint256 startAmount = 21;
        int256[] memory amounts = new int256[](1);
        amounts[0] = 1;
        NonlinearDutchDecay memory curve = NonlinearDutchDecay(1, amounts);
        address recipient = address(0);
        uint256 minAmount = 20;
        uint256 adjustmentPerGweiBaseFee = 0;
        V3DutchOutput memory output =
            V3DutchOutput(token, startAmount, curve, recipient, minAmount, adjustmentPerGweiBaseFee);
        assertEq(V3DutchOrderLib.hash(output), hex"c57ac5e0436939ec593af412dde4a05d4972a0a8a56bbdb63ca7cd949c5326e2");
    }

    function test_OrderTypeHash() public pure {
        assertEq(V3DutchOrderLib.ORDER_TYPE_HASH, hex"186c8af0344af94faab60c9dc413f68b8ca7aea1aded04a300c7fa35562ed1b7");
    }
}

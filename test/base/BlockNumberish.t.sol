import {Test} from "forge-std/Test.sol";
import {MockArbSys} from "../util/mock/MockArbSys.sol";
import {BlockNumberish} from "../../src/base/BlockNumberish.sol";

contract MockBlockNumberish is BlockNumberish {
    function getBlockNumberish() external view returns (uint256) {
        return _getBlockNumberish();
    }
}

contract BlockNumberishTest is Test {
    MockArbSys arbSys;
    MockBlockNumberish blockNumberish;

    function setUp() public {
        // etch MockArbSys to address(100)
        vm.etch(address(100), address(new MockArbSys()).code);
        arbSys = MockArbSys(address(100));
    }

    function test_getBlockNumber() public {
        blockNumberish = new MockBlockNumberish();

        vm.roll(100);
        assertEq(blockNumberish.getBlockNumberish(), 100);
    }

    function test_getBlockNumberSyscall() public {
        vm.chainId(42161);
        blockNumberish = new MockBlockNumberish();

        arbSys.setBlockNumber(1);
        assertEq(blockNumberish.getBlockNumberish(), 1);
    }
}

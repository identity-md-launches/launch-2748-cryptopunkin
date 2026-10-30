// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The subset of Foundry's cheatcodes these tests use, declared here so the project has
/// no external dependency. Every signature matches forge's `Vm` interface; the cheatcode contract
/// lives at `address(uint160(uint256(keccak256("hevm cheat code"))))`.
interface Vm {
    /// @notice Sets `msg.sender` for the next call only.
    function prank(address msgSender) external;
    /// @notice Sets `msg.sender` for every call until `stopPrank`.
    function startPrank(address msgSender) external;
    /// @notice Ends a `startPrank`.
    function stopPrank() external;
    /// @notice Expects the next call to revert with exactly `revertData`.
    function expectRevert(bytes calldata revertData) external;
    /// @notice Expects the next call to revert with a custom error of selector `revertData`.
    function expectRevert(bytes4 revertData) external;
    /// @notice Expects the next call to emit the event emitted right after this cheatcode.
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    /// @notice Discards a fuzz input when `condition` is false.
    function assume(bool condition) external pure;
    /// @notice Labels `account` in traces.
    function label(address account, string calldata newLabel) external;
    /// @notice Starts recording calls as transactions to broadcast (scripts only).
    function startBroadcast() external;
    /// @notice Stops recording broadcast transactions (scripts only).
    function stopBroadcast() external;
}

/// @notice A small, dependency-free base for forge tests: the cheatcode handle plus the assertions
/// this project needs. Every assertion reverts with a readable message on failure, which forge
/// reports as a failing test.
abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool condition, string memory err) internal pure {
        if (!condition) revert(string.concat("assertTrue failed: ", err));
    }

    function assertFalse(bool condition, string memory err) internal pure {
        if (condition) revert(string.concat("assertFalse failed: ", err));
    }

    function assertEq(uint256 left, uint256 right, string memory err) internal pure {
        if (left != right) {
            revert(string.concat("assertEq failed: ", err, " (", toString(left), " != ", toString(right), ")"));
        }
    }

    function assertEq(address left, address right, string memory err) internal pure {
        if (left != right) revert(string.concat("assertEq(address) failed: ", err));
    }

    function assertEq(bool left, bool right, string memory err) internal pure {
        if (left != right) revert(string.concat("assertEq(bool) failed: ", err));
    }

    function assertEq(string memory left, string memory right, string memory err) internal pure {
        if (keccak256(bytes(left)) != keccak256(bytes(right))) {
            revert(string.concat("assertEq(string) failed: ", err, " (", left, " != ", right, ")"));
        }
    }

    function assertLe(uint256 left, uint256 right, string memory err) internal pure {
        if (left > right) {
            revert(string.concat("assertLe failed: ", err, " (", toString(left), " > ", toString(right), ")"));
        }
    }

    function assertGt(uint256 left, uint256 right, string memory err) internal pure {
        if (left <= right) {
            revert(string.concat("assertGt failed: ", err, " (", toString(left), " <= ", toString(right), ")"));
        }
    }

    /// @notice Maps any fuzzed value into `[min, max]` without rejecting inputs, so a fuzz run never
    /// runs out of accepted cases whatever seed the verifier uses.
    function bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        require(min <= max, "bound: min > max");
        uint256 size = max - min;
        if (size == type(uint256).max) return value;
        return min + (value % (size + 1));
    }

    /// @notice Decimal rendering of an unsigned integer for assertion messages.
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 digits;
        for (uint256 probe = value; probe != 0; probe /= 10) {
            ++digits;
        }
        bytes memory buffer = new bytes(digits);
        for (uint256 rest = value; rest != 0; rest /= 10) {
            --digits;
            buffer[digits] = bytes1(uint8(48 + rest % 10));
        }
        return string(buffer);
    }
}

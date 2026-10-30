// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {CryptoPunkin} from "../src/CryptoPunkin.sol";
import {DeployCryptoPunkin} from "../script/DeployCryptoPunkin.s.sol";

/// @notice The deploy script's `deploy()` function, called directly with no environment.
contract DeployCryptoPunkinTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function test_deployMintsSupplyToTheScriptContract() public {
        DeployCryptoPunkin script = new DeployCryptoPunkin();
        CryptoPunkin token = script.deploy();
        assertEq(token.totalSupply(), SUPPLY, "supply");
        assertEq(token.balanceOf(address(script)), SUPPLY, "the script contract, as deployer, holds the supply");
        assertEq(token.balanceOf(address(this)), 0, "the test holds nothing");
        assertEq(token.name(), "CryptoPunkin", "name");
        assertEq(token.symbol(), "PUNKINS", "symbol");
    }

    function test_deployTwiceGivesTwoIndependentTokens() public {
        DeployCryptoPunkin script = new DeployCryptoPunkin();
        CryptoPunkin first = script.deploy();
        CryptoPunkin second = script.deploy();
        assertFalse(address(first) == address(second), "distinct addresses");
        assertEq(first.balanceOf(address(script)), SUPPLY, "first supply");
        assertEq(second.balanceOf(address(script)), SUPPLY, "second supply");
    }
}

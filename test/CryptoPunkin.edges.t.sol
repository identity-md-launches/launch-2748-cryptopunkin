// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {CryptoPunkin} from "../src/CryptoPunkin.sol";

/// @notice Edge inputs CryptoPunkinTest leaves out: zero values against zero allowances, an unlimited
/// allowance against a short balance, sending to oneself through transferFrom, the full supply through
/// an allowance, and fuzzed senders and receivers including the token's own address.
contract CryptoPunkinEdgesTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    CryptoPunkin internal token;

    function setUp() public {
        token = new CryptoPunkin();
    }

    function test_zeroValueTransferFromNeedsNoAllowance() public {
        vm.prank(BOB);
        assertTrue(token.transferFrom(address(this), CAROL, 0), "zero transferFrom returns true");
        assertEq(token.allowance(address(this), BOB), 0, "allowance still zero");
        assertEq(token.balanceOf(address(this)), SUPPLY, "nothing moved");
    }

    function test_unlimitedAllowanceStillBoundedByBalance() public {
        token.transfer(ALICE, 5e18);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientBalance.selector, ALICE, 5e18, 5e18 + 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 5e18 + 1);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max, "unlimited allowance untouched");
        assertEq(token.balanceOf(ALICE), 5e18, "balance untouched");
    }

    function test_unlimitedAllowanceMovesTheWholeSupplyRepeatedly() public {
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, SUPPLY);
        assertEq(token.balanceOf(ALICE), SUPPLY, "alice holds everything");
        vm.prank(ALICE);
        token.transfer(address(this), SUPPLY);
        vm.prank(BOB);
        token.transferFrom(address(this), CAROL, SUPPLY);
        assertEq(token.balanceOf(CAROL), SUPPLY, "carol holds everything");
        assertEq(token.allowance(address(this), BOB), type(uint256).max, "still unlimited");
    }

    function test_allowanceOneBelowMaxIsFinite() public {
        token.approve(BOB, type(uint256).max - 1);
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), BOB), type(uint256).max - 2, "a finite allowance is spent");
    }

    function test_transferFromToSelfSpendsAllowanceKeepsBalance() public {
        token.transfer(ALICE, 10e18);
        vm.prank(ALICE);
        token.approve(BOB, 4e18);
        vm.prank(BOB);
        token.transferFrom(ALICE, ALICE, 4e18);
        assertEq(token.balanceOf(ALICE), 10e18, "balance unchanged");
        assertEq(token.allowance(ALICE, BOB), 0, "allowance spent");
    }

    function test_ownerCanSpendOwnBalanceAfterApprovingItself() public {
        token.approve(address(this), 3e18);
        token.transferFrom(address(this), ALICE, 3e18);
        assertEq(token.balanceOf(ALICE), 3e18, "alice received");
        assertEq(token.allowance(address(this), address(this)), 0, "self allowance spent");
    }

    function test_selfTransferAboveBalanceReverts() public {
        token.transfer(ALICE, 1e18);
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientBalance.selector, ALICE, 1e18, 1e18 + 1));
        vm.prank(ALICE);
        token.transfer(ALICE, 1e18 + 1);
    }

    function test_maxValueTransferRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CryptoPunkin.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
    }

    function test_tokensSentToTheTokenItselfAreStuckButCounted() public {
        token.transfer(address(token), 1e18);
        assertEq(token.balanceOf(address(token)), 1e18, "the token's own address holds them");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function testFuzz_anyPairConservesBalances(address from, address to, uint256 seeded, uint256 amount) public {
        from = from == address(0) ? ALICE : from;
        to = to == address(0) ? BOB : to;
        if (from == address(this)) from = CAROL;
        seeded = bound(seeded, 0, SUPPLY);
        amount = bound(amount, 0, seeded);
        token.transfer(from, seeded);
        uint256 before = token.balanceOf(from) + (from == to ? 0 : token.balanceOf(to));
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer returns true");
        uint256 afterwards = token.balanceOf(from) + (from == to ? 0 : token.balanceOf(to));
        assertEq(afterwards, before, "the pair's total is conserved");
        if (from != to) assertEq(token.balanceOf(to), amount, "receiver credited exactly");
        assertEq(token.balanceOf(address(this)), SUPPLY - seeded, "a bystander is untouched");
    }

    function testFuzz_failedTransferFromChangesNothing(uint256 balance, uint256 allowed) public {
        balance = bound(balance, 0, SUPPLY);
        allowed = bound(allowed, 0, SUPPLY);
        // Make the call fail: ask for one more than the binding limit.
        uint256 value = (balance < allowed ? balance : allowed) + 1;
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(BOB, allowed);
        bytes memory expected = allowed < value
            ? abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientAllowance.selector, BOB, allowed, value)
            : abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientBalance.selector, ALICE, balance, value);
        vm.expectRevert(expected);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, value);
        assertEq(token.balanceOf(ALICE), balance, "balance unchanged");
        assertEq(token.balanceOf(CAROL), 0, "nothing arrived");
        assertEq(token.allowance(ALICE, BOB), allowed, "allowance unchanged");
    }
}

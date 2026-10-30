// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {CryptoPunkin} from "../src/CryptoPunkin.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @notice Deploys the token from a contract so the test can check that the supply lands on the
/// deployer, whoever that is, and not on the test contract or on `tx.origin`.
contract DeployerProbe {
    CryptoPunkin public immutable token;

    constructor() {
        token = new CryptoPunkin();
    }

    function payOut(address to, uint256 value) external returns (bool) {
        return token.transfer(to, value);
    }
}

/// @notice Behaviour of CryptoPunkin (PUNKINS): metadata, the one-time mint, transfers, approvals,
/// their failure modes, and the absence of any privileged or supply-changing path.
contract CryptoPunkinTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);
    address internal constant STRANGER = address(0x5712A);

    CryptoPunkin internal token;
    /// @dev The address that deployed the token in `setUp`: this test contract.
    address internal deployer;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = address(this);
        token = new CryptoPunkin();
        vm.label(address(token), "PUNKINS");
        vm.label(ALICE, "alice");
        vm.label(BOB, "bob");
        vm.label(CAROL, "carol");
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and the one-time mint
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "CryptoPunkin", "name");
        assertEq(token.symbol(), "PUNKINS", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.totalSupply(), SUPPLY, "totalSupply");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY, "TOTAL_SUPPLY constant");
        assertEq(token.totalSupply(), 1_000_000_000 * 1e18, "supply as whole tokens times one token");
        assertEq(token.totalSupply() / 10 ** uint256(token.decimals()), 1_000_000_000, "one billion whole tokens");
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(deployer), SUPPLY, "deployer holds everything");
        assertEq(token.balanceOf(address(0)), 0, "nothing at the zero address");
    }

    function test_supplyGoesToTheDeployingContractNotTheTestOrOrigin() public {
        DeployerProbe probe = new DeployerProbe();
        CryptoPunkin deployed = probe.token();
        assertEq(deployed.balanceOf(address(probe)), SUPPLY, "the deploying contract holds the supply");
        assertEq(deployed.balanceOf(address(this)), 0, "the test holds none of it");
        assertEq(deployed.balanceOf(tx.origin), 0, "tx.origin holds none of it");
        assertTrue(probe.payOut(ALICE, 1e18), "the deployer can pay out");
        assertEq(deployed.balanceOf(ALICE), 1e18, "payout arrived whole");
    }

    function test_eachDeploymentHasItsOwnSupply() public {
        CryptoPunkin second = new CryptoPunkin();
        assertEq(second.totalSupply(), SUPPLY, "second supply");
        assertEq(second.balanceOf(deployer), SUPPLY, "second deployer balance");
        assertEq(token.balanceOf(deployer), SUPPLY, "first balance untouched");
    }

    // ---------------------------------------------------------------------------------------------
    // transfer
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1_234e18;
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, ALICE, amount);
        assertTrue(token.transfer(ALICE, amount), "transfer returns true");
        assertEq(token.balanceOf(ALICE), amount, "alice received");
        assertEq(token.balanceOf(deployer), SUPPLY - amount, "deployer debited");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferWholeBalance() public {
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(ALICE), SUPPLY, "alice holds everything");
        assertEq(token.balanceOf(deployer), 0, "deployer emptied");
    }

    function test_transferZeroValueSucceedsAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0), "zero transfer returns true");
        assertEq(token.balanceOf(BOB), 0, "bob still has nothing");
    }

    function test_transferToSelfKeepsBalance() public {
        token.transfer(ALICE, 100e18);
        vm.prank(ALICE);
        token.transfer(ALICE, 60e18);
        assertEq(token.balanceOf(ALICE), 100e18, "self transfer keeps the balance");
    }

    function test_transferChainsBetweenHolders() public {
        token.transfer(ALICE, 300e18);
        vm.prank(ALICE);
        token.transfer(BOB, 200e18);
        vm.prank(BOB);
        token.transfer(CAROL, 50e18);
        assertEq(token.balanceOf(ALICE), 100e18, "alice");
        assertEq(token.balanceOf(BOB), 150e18, "bob");
        assertEq(token.balanceOf(CAROL), 50e18, "carol");
        assertEq(token.balanceOf(deployer), SUPPLY - 300e18, "deployer");
    }

    function test_transferRevertsOnInsufficientBalance() public {
        token.transfer(ALICE, 10e18);
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientBalance.selector, ALICE, 10e18, 10e18 + 1));
        vm.prank(ALICE);
        token.transfer(BOB, 10e18 + 1);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientBalance.selector, STRANGER, 0, 1));
        vm.prank(STRANGER);
        token.transfer(BOB, 1);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1e18);
    }

    function test_transferToZeroAddressRevertsEvenForZeroValue() public {
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    // ---------------------------------------------------------------------------------------------
    // approve / allowance
    // ---------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, BOB, 500e18);
        assertTrue(token.approve(BOB, 500e18), "approve returns true");
        assertEq(token.allowance(deployer, BOB), 500e18, "allowance set");
        assertEq(token.allowance(BOB, deployer), 0, "allowance is directional");
    }

    function test_approveOverwritesNotAccumulates() public {
        token.approve(BOB, 500e18);
        token.approve(BOB, 20e18);
        assertEq(token.allowance(deployer, BOB), 20e18, "second approve replaces the first");
        token.approve(BOB, 0);
        assertEq(token.allowance(deployer, BOB), 0, "approve to zero clears");
    }

    function test_approveDoesNotRequireBalance() public {
        vm.prank(STRANGER);
        assertTrue(token.approve(BOB, SUPPLY), "an empty account may approve");
        assertEq(token.allowance(STRANGER, BOB), SUPPLY, "allowance recorded");
    }

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // transferFrom
    // ---------------------------------------------------------------------------------------------

    function test_transferFromSpendsAllowance() public {
        token.transfer(ALICE, 100e18);
        vm.prank(ALICE);
        token.approve(BOB, 60e18);

        vm.expectEmit(true, true, true, true);
        emit Transfer(ALICE, CAROL, 40e18);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, 40e18), "transferFrom returns true");

        assertEq(token.balanceOf(ALICE), 60e18, "alice debited");
        assertEq(token.balanceOf(CAROL), 40e18, "carol credited");
        assertEq(token.balanceOf(BOB), 0, "the spender holds nothing");
        assertEq(token.allowance(ALICE, BOB), 20e18, "allowance reduced");
    }

    function test_transferFromExactAllowanceLeavesZero() public {
        token.transfer(ALICE, 100e18);
        vm.prank(ALICE);
        token.approve(BOB, 100e18);
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 100e18);
        assertEq(token.allowance(ALICE, BOB), 0, "allowance exhausted");
        assertEq(token.balanceOf(BOB), 100e18, "bob received");
        assertEq(token.balanceOf(ALICE), 0, "alice emptied");
    }

    function test_transferFromUnlimitedAllowanceIsNotDecremented() public {
        token.transfer(ALICE, 100e18);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 70e18);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max, "unlimited stays unlimited");
        assertEq(token.balanceOf(CAROL), 70e18, "carol received");
    }

    function test_transferFromRevertsWithoutAllowance() public {
        token.transfer(ALICE, 100e18);
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
    }

    function test_transferFromRevertsAboveAllowance() public {
        token.transfer(ALICE, 100e18);
        vm.prank(ALICE);
        token.approve(BOB, 10e18);
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientAllowance.selector, BOB, 10e18, 10e18 + 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 10e18 + 1);
    }

    function test_transferFromRevertsAboveBalanceEvenWithAllowance() public {
        token.transfer(ALICE, 5e18);
        vm.prank(ALICE);
        token.approve(BOB, 10e18);
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientBalance.selector, ALICE, 5e18, 6e18));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 6e18);
        assertEq(token.allowance(ALICE, BOB), 10e18, "a failed transfer spends no allowance");
    }

    function test_transferFromRevertsToZeroAddress() public {
        token.approve(BOB, 10e18);
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(deployer, address(0), 1);
    }

    function test_transferFromRevertsFromZeroAddress() public {
        // Nobody can approve on behalf of address(0), so only a zero value reaches _transfer.
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InvalidSender.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(address(0), BOB, 0);
    }

    function test_transferFromOnlySpendsTheCallersOwnAllowance() public {
        token.transfer(ALICE, 100e18);
        vm.prank(ALICE);
        token.approve(BOB, 100e18);
        // Carol has no allowance from Alice; Bob's allowance does not help her.
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientAllowance.selector, CAROL, 0, 1));
        vm.prank(CAROL);
        token.transferFrom(ALICE, CAROL, 1);
        assertEq(token.allowance(ALICE, BOB), 100e18, "bob's allowance untouched");
    }

    function test_selfTransferFromRequiresAllowance() public {
        // The caller is not implicitly allowed to spend its own balance through transferFrom.
        token.transfer(ALICE, 10e18);
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientAllowance.selector, ALICE, 0, 1e18));
        vm.prank(ALICE);
        token.transferFrom(ALICE, BOB, 1e18);
    }

    // ---------------------------------------------------------------------------------------------
    // No privileged or supply-changing paths
    // ---------------------------------------------------------------------------------------------

    function test_noMintOrAdminSelectorIsAnswered() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "setBlacklist(address,bool)",
            "freeze(address)",
            "upgradeTo(address)",
            "initialize(address)"
        ];
        token.transfer(ALICE, 1e18);
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, uint256(1e18));
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(STRANGER);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
        assertEq(token.balanceOf(ALICE), 1e18, "alice's balance untouched");
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1e18), "alice can still transfer");
    }

    function test_rejectsPlainEtherAndUnknownCalls() public {
        (bool ok,) = address(token).call{value: 0}("");
        assertFalse(ok, "no receive function");
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok, "no fallback function");
    }

    function test_deployerHasNoSpecialPowerOverHolders() public {
        token.transfer(ALICE, 100e18);
        vm.expectRevert(abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(ALICE, deployer, 1);
        assertEq(token.balanceOf(ALICE), 100e18, "the deployer cannot pull a holder's tokens");
    }

    function test_interfaceConformance() public view {
        IERC20 erc20 = IERC20(address(token));
        assertEq(erc20.totalSupply(), SUPPLY, "IERC20.totalSupply");
        assertEq(erc20.balanceOf(deployer), SUPPLY, "IERC20.balanceOf");
        assertEq(uint256(erc20.decimals()), 18, "IERC20.decimals");
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz: conservation and arithmetic across the whole input space
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), amount, "receiver credited");
        assertEq(token.balanceOf(deployer), SUPPLY - amount, "sender debited");
        assertEq(token.balanceOf(to) + token.balanceOf(deployer), SUPPLY, "conserved");
        assertEq(token.totalSupply(), SUPPLY, "supply fixed");
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 excess) public {
        held = bound(held, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - held);
        token.transfer(ALICE, held);
        vm.expectRevert(
            abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientBalance.selector, ALICE, held, held + excess)
        );
        vm.prank(ALICE);
        token.transfer(BOB, held + excess);
        assertEq(token.balanceOf(ALICE), held, "balance untouched after revert");
    }

    function testFuzz_approveThenTransferFrom(uint256 allowed, uint256 spent) public {
        allowed = bound(allowed, 0, SUPPLY);
        spent = bound(spent, 0, allowed);
        token.approve(BOB, allowed);
        vm.prank(BOB);
        token.transferFrom(deployer, CAROL, spent);
        assertEq(token.balanceOf(CAROL), spent, "carol received what was spent");
        assertEq(token.balanceOf(deployer), SUPPLY - spent, "deployer debited");
        assertEq(token.allowance(deployer, BOB), allowed - spent, "allowance decremented exactly");
    }

    function testFuzz_transferFromAboveAllowanceReverts(uint256 allowed, uint256 excess) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - allowed);
        token.approve(BOB, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientAllowance.selector, BOB, allowed, allowed + excess)
        );
        vm.prank(BOB);
        token.transferFrom(deployer, CAROL, allowed + excess);
        assertEq(token.allowance(deployer, BOB), allowed, "allowance untouched after revert");
        assertEq(token.balanceOf(CAROL), 0, "nothing moved");
    }

    function testFuzz_allowanceIsPerOwnerSpenderPair(address owner, address spender, uint256 value) public {
        vm.assume(spender != address(0));
        vm.assume(owner != spender);
        vm.prank(owner);
        token.approve(spender, value);
        assertEq(token.allowance(owner, spender), value, "set for the pair");
        assertEq(token.allowance(spender, owner), 0, "not set in reverse");
    }
}

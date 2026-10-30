// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase, Vm} from "./utils/TestBase.sol";
import {CryptoPunkin} from "../src/CryptoPunkin.sol";

/// @notice Drives CryptoPunkin with random transfers, approvals and transferFroms between a fixed set
/// of actors, some of them meant to fail. It deploys the token itself, so it starts as the holder of
/// the whole supply, and keeps its own model of every balance and allowance. Before each call it
/// predicts from the model whether the call succeeds and, if not, the exact error; any disagreement
/// with the token reverts the handler, which the invariant runner reports as a failure.
contract PunkinsHandler {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 internal constant MAX = type(uint256).max;

    CryptoPunkin public immutable token;
    address[] internal actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostMoved;
    uint256 public successfulCalls;
    uint256 public failedCalls;
    /// @dev Set once an unlimited allowance has been used to move a non-zero amount.
    uint256 public unlimitedSpends;

    constructor() {
        token = new CryptoPunkin();
        actors.push(address(this));
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA201));
        actors.push(address(0xD0D0));
        ghostBalance[address(this)] = SUPPLY;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Mostly an actor; one time in eight, the zero address, which must always be refused.
    function _receiver(uint256 seed) internal view returns (address) {
        if (seed % 8 == 7) return address(0);
        return _actor(seed / 8);
    }

    /// @dev Mostly within what is available; sometimes exactly it, one wei over, or anything at all.
    function _amount(uint256 seed, uint256 available) internal pure returns (uint256) {
        uint256 mode = seed % 10;
        uint256 raw = seed / 10;
        if (mode == 0) return available;
        if (mode == 1) return available == MAX ? MAX : available + 1;
        if (mode == 2) return 0;
        if (mode == 3) return raw;
        uint256 cap = available > SUPPLY ? SUPPLY : available;
        return raw % (cap + 1);
    }

    function _check(bool ok, string memory err) internal pure {
        if (!ok) revert(string.concat("handler: ", err));
    }

    function _snapshotMatches(address a, address b) internal view returns (bool) {
        return token.balanceOf(a) == ghostBalance[a] && token.balanceOf(b) == ghostBalance[b];
    }

    function _applyTransfer(address from, address to, uint256 value) internal {
        ghostBalance[from] -= value;
        ghostBalance[to] += value;
        ghostMoved += value;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _receiver(toSeed);
        uint256 value = _amount(amountSeed, ghostBalance[from]);

        bytes memory expectedError;
        if (to == address(0)) {
            expectedError = abi.encodeWithSelector(CryptoPunkin.ERC20InvalidReceiver.selector, address(0));
        } else if (ghostBalance[from] < value) {
            expectedError =
                abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientBalance.selector, from, ghostBalance[from], value);
        }

        vm.prank(from);
        try token.transfer(to, value) returns (bool ok) {
            _check(expectedError.length == 0, "transfer succeeded where it had to revert");
            _check(ok, "transfer returned false");
            _applyTransfer(from, to, value);
            ++successfulCalls;
        } catch (bytes memory err) {
            _check(expectedError.length != 0, "transfer reverted where it had to succeed");
            _check(keccak256(err) == keccak256(expectedError), "transfer reverted with the wrong error");
            ++failedCalls;
        }
        _check(_snapshotMatches(from, to == address(0) ? from : to), "transfer balances diverge from the model");
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _receiver(spenderSeed);
        // Unlimited one time in four, so transferFrom exercises the non-decrementing path.
        uint256 value = amountSeed % 4 == 0 ? MAX : _amount(amountSeed / 4, ghostBalance[owner]);

        vm.prank(owner);
        try token.approve(spender, value) returns (bool ok) {
            _check(spender != address(0), "approve accepted the zero spender");
            _check(ok, "approve returned false");
            ghostAllowance[owner][spender] = value;
            ++successfulCalls;
        } catch (bytes memory err) {
            _check(spender == address(0), "approve reverted for a real spender");
            _check(
                keccak256(err)
                    == keccak256(abi.encodeWithSelector(CryptoPunkin.ERC20InvalidSpender.selector, address(0))),
                "approve reverted with the wrong error"
            );
            ++failedCalls;
        }
        _check(token.allowance(owner, spender) == ghostAllowance[owner][spender], "allowance diverges from the model");
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _receiver(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 available = ghostBalance[from] < allowed ? ghostBalance[from] : allowed;
        // Aim at whichever limit binds, and sometimes at the other one.
        if (amountSeed % 5 == 0) available = amountSeed % 2 == 0 ? allowed : ghostBalance[from];
        uint256 value = _amount(amountSeed / 5, available);

        bytes memory expectedError;
        if (allowed != MAX && allowed < value) {
            expectedError =
                abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientAllowance.selector, spender, allowed, value);
        } else if (to == address(0)) {
            expectedError = abi.encodeWithSelector(CryptoPunkin.ERC20InvalidReceiver.selector, address(0));
        } else if (ghostBalance[from] < value) {
            expectedError =
                abi.encodeWithSelector(CryptoPunkin.ERC20InsufficientBalance.selector, from, ghostBalance[from], value);
        }

        vm.prank(spender);
        try token.transferFrom(from, to, value) returns (bool ok) {
            _check(expectedError.length == 0, "transferFrom succeeded where it had to revert");
            _check(ok, "transferFrom returned false");
            if (allowed != MAX) ghostAllowance[from][spender] = allowed - value;
            else if (value != 0) ++unlimitedSpends;
            _applyTransfer(from, to, value);
            ++successfulCalls;
        } catch (bytes memory err) {
            _check(expectedError.length != 0, "transferFrom reverted where it had to succeed");
            _check(keccak256(err) == keccak256(expectedError), "transferFrom reverted with the wrong error");
            ++failedCalls;
        }
        _check(
            token.allowance(from, spender) == ghostAllowance[from][spender],
            "transferFrom allowance diverges from the model"
        );
        _check(_snapshotMatches(from, to == address(0) ? from : to), "transferFrom balances diverge from the model");
    }
}

/// @notice Properties of CryptoPunkin that must hold after any sequence of calls: the supply is fixed
/// and fully accounted for by the actors, every balance and allowance matches the handler's model,
/// nothing ever lands on the zero address, and the token holds no ether.
contract CryptoPunkinInvariantTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    PunkinsHandler internal handler;
    CryptoPunkin internal token;

    function setUp() public {
        handler = new PunkinsHandler();
        token = handler.token();
        vm.label(address(handler), "handler");
        vm.label(address(token), "PUNKINS");
    }

    /// @dev Read by forge's invariant runner: only the handler is called, never the token directly,
    /// so every call goes through the model.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY, "totalSupply");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY, "TOTAL_SUPPLY");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_actorsHoldTheWholeSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            uint256 held = token.balanceOf(handler.actorAt(i));
            assertLe(held, SUPPLY, "a balance exceeds the supply");
            sum += held;
        }
        assertEq(sum, SUPPLY, "sum of balances");
        assertEq(token.balanceOf(address(0)), 0, "the zero address holds tokens");
        assertEq(token.balanceOf(address(token)), 0, "the token holds its own tokens");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesAndAllowancesMatchTheModel() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address owner = handler.actorAt(i);
            assertEq(token.balanceOf(owner), handler.ghostBalance(owner), "balance vs model");
            for (uint256 j; j < n; ++j) {
                address spender = handler.actorAt(j);
                assertEq(token.allowance(owner, spender), handler.ghostAllowance(owner, spender), "allowance vs model");
            }
            assertEq(token.allowance(owner, address(0)), 0, "an allowance for the zero spender exists");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_tokenHoldsNoEther() public view {
        assertEq(address(token).balance, 0, "ether in the token");
    }

    /// @dev The handler is not vacuous: a fixed sequence through it reaches successes, every failure
    /// kind, and the unlimited-allowance path, with the model agreeing at each step.
    function test_handlerExercisesEveryPath() public {
        // Seeds: actor index = seed % 5 (0 is the handler, the holder); receiver seed 7 is address(0).
        handler.transfer(0, 8 * 1, 9 * 10 + 4); // handler -> alice, a bounded amount
        handler.transfer(0, 7, 4); // to the zero address: refused
        handler.transfer(1, 8 * 2, 1); // alice -> bob, one wei over her balance: refused
        handler.transfer(1, 8 * 2, 0); // alice -> bob, her whole balance
        handler.approve(2, 8 * 3, 0); // bob lets carol spend without limit
        handler.approve(2, 7, 1); // the zero spender: refused
        handler.transferFrom(3, 2, 8 * 4, 5 * 0 + 1); // carol moves bob's whole balance to dave
        handler.transferFrom(4, 0, 8 * 1, 5 * 1 + 1); // dave has no allowance from the handler: refused
        handler.approve(0, 8 * 4, 4 * 40 + 1); // the handler lets dave spend a bounded amount
        handler.transferFrom(4, 0, 7, 5 * 2 + 1); // to the zero address: refused
        handler.transferFrom(4, 0, 8 * 1, 5 * 0 + 1); // exactly the allowance
        assertGt(handler.successfulCalls(), 4, "successes");
        assertGt(handler.failedCalls(), 4, "failures");
        assertGt(handler.ghostMoved(), 0, "tokens moved");
        invariant_actorsHoldTheWholeSupply();
        invariant_balancesAndAllowancesMatchTheModel();
    }
}

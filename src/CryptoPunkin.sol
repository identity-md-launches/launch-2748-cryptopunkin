// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title CryptoPunkin (PUNKINS)
/// @notice A fixed-supply ERC-20 token. The whole supply of 1,000,000,000 PUNKINS (18 decimals) is
/// minted once, in the constructor, to the deployer. Nothing can mint afterwards, nothing can burn,
/// and no address has any privilege: there is no owner, no pause, no blocklist and no fee.
/// @dev The contract has no dependencies. It follows the ERC-20 standard with OpenZeppelin v5's
/// custom-error conventions so wallets, explorers and routers decode its reverts.
///
/// Design notes:
/// - `totalSupply()` is a compile-time constant, so the supply is structurally fixed: there is no
///   mint path, no burn path and no storage variable that could drift from it.
/// - `approve` overwrites the allowance (ERC-20 semantics). Holders who change a non-zero allowance
///   should set it to zero first if they worry about the well-known approve race.
/// - The constructor takes no arguments and calls no other contract, so it deploys on an empty
///   chain and its creation bytecode is reproducible from the pinned compiler settings.
contract CryptoPunkin is IERC20 {
    /// @notice Thrown when a transfer names `address(0)` as the sender.
    error ERC20InvalidSender(address sender);
    /// @notice Thrown when a transfer names `address(0)` as the receiver.
    error ERC20InvalidReceiver(address receiver);
    /// @notice Thrown when `sender` holds `balance` but a transfer of `needed` was requested.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    /// @notice Thrown when an approval names `address(0)` as the spender.
    error ERC20InvalidSpender(address spender);
    /// @notice Thrown when `spender` was allowed `allowance` but tried to move `needed`.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @dev The token's full name.
    string private constant TOKEN_NAME = "CryptoPunkin";
    /// @dev The token's ticker symbol.
    string private constant TOKEN_SYMBOL = "PUNKINS";
    /// @dev Decimals of the minor unit.
    uint8 private constant TOKEN_DECIMALS = 18;
    /// @notice The fixed total supply: 1,000,000,000 whole tokens in minor units.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(TOKEN_DECIMALS);

    mapping(address account => uint256 balance) private _balances;
    mapping(address owner => mapping(address spender => uint256 value)) private _allowances;

    /// @notice Mints the whole supply to the deployer (`msg.sender`), once.
    constructor() {
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc IERC20
    function name() external pure override returns (string memory) {
        return TOKEN_NAME;
    }

    /// @inheritdoc IERC20
    function symbol() external pure override returns (string memory) {
        return TOKEN_SYMBOL;
    }

    /// @inheritdoc IERC20
    function decimals() external pure override returns (uint8) {
        return TOKEN_DECIMALS;
    }

    /// @inheritdoc IERC20
    function totalSupply() external pure override returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 value) external override returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @inheritdoc IERC20
    /// @dev Only the caller's own allowance from `from` is spent. An allowance of `type(uint256).max`
    /// is treated as unlimited and is not decremented, as in OpenZeppelin's ERC20.
    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 current = _allowances[from][msg.sender];
        if (current != type(uint256).max) {
            if (current < value) revert ERC20InsufficientAllowance(msg.sender, current, value);
            unchecked {
                _allowances[from][msg.sender] = current - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    /// @dev Moves `value` from `from` to `to`. Reverts on a zero address at either end or on an
    /// insufficient balance. A zero-value transfer is valid and emits an event, per ERC-20.
    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert ERC20InsufficientBalance(from, fromBalance, value);
        unchecked {
            // Underflow is excluded by the check above. Overflow is impossible: the sum of all
            // balances is the constant TOTAL_SUPPLY, which fits in a uint256 with room to spare.
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }
}

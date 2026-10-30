// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IERC20
/// @notice The ERC-20 interface (EIP-20) together with the optional metadata extension.
interface IERC20 {
    /// @notice Emitted when `value` tokens move from `from` to `to`. A mint has `from == address(0)`.
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when `owner` sets the allowance of `spender` to `value`.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice The token's full name.
    function name() external view returns (string memory);

    /// @notice The token's ticker symbol.
    function symbol() external view returns (string memory);

    /// @notice The number of decimals the token's minor unit is scaled by.
    function decimals() external view returns (uint8);

    /// @notice The number of tokens in existence, in minor units.
    function totalSupply() external view returns (uint256);

    /// @notice The number of tokens `account` holds, in minor units.
    function balanceOf(address account) external view returns (uint256);

    /// @notice The number of tokens `spender` may still move out of `owner`'s balance.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Moves `value` tokens from the caller to `to`.
    function transfer(address to, uint256 value) external returns (bool);

    /// @notice Sets the caller's allowance for `spender` to `value`.
    function approve(address spender, uint256 value) external returns (bool);

    /// @notice Moves `value` tokens from `from` to `to`, spending the caller's allowance from `from`.
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/token-standards/IERC20.sol";
import "./interfaces/token-standards/IWETH.sol";

/// @title TokenHelper
/// @notice Token utility functions for whitehat attack contracts
/// @dev Provides balance tracking, approvals, and safe transfers
abstract contract TokenHelper {

    // ============ Constants ============

    uint256 internal constant MAX_UINT256 = type(uint256).max;

    // ============ State ============

    address public weth;

    /// @notice Balance snapshots for profit calculation
    mapping(address => uint256) private _snapshots;

    // ============ Errors ============

    error TransferFailed();
    error ApprovalFailed();
    error InsufficientBalance();

    // ============ Balance Utilities ============

    /// @notice Get token balance of this contract
    function _balanceOf(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Get ETH balance of this contract
    function _ethBalance() internal view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Get token balance of any address
    function _balanceOf(address token, address account) internal view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }

    /// @notice Get multiple token balances of this contract
    function _balancesOf(address[] memory tokens) internal view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
    }

    /// @notice Check if contract has sufficient balance
    function _hasBalance(address token, uint256 amount) internal view returns (bool) {
        return IERC20(token).balanceOf(address(this)) >= amount;
    }

    // ============ Snapshot Utilities ============

    /// @notice Take a snapshot of current token balance
    function _snapshotTokens(address token) internal {
        _snapshots[token] = IERC20(token).balanceOf(address(this));
    }

    /// @notice Take a snapshot of ETH balance (stored at address(0))
    function _snapshotETH() internal {
        _snapshots[address(0)] = address(this).balance;
    }

    /// @notice Take snapshots of multiple tokens
    function _snapshotMultiple(address[] memory tokens) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            _snapshots[tokens[i]] = IERC20(tokens[i]).balanceOf(address(this));
        }
    }

    /// @notice Get profit since snapshot (current - snapshot)
    /// @return profit Positive if gained, negative values return 0
    function _profitSince(address token) internal view returns (uint256 profit) {
        uint256 current = IERC20(token).balanceOf(address(this));
        uint256 snapshot = _snapshots[token];
        profit = current > snapshot ? current - snapshot : 0;
    }

    /// @notice Get ETH profit since snapshot
    function _ethProfitSince() internal view returns (uint256 profit) {
        uint256 current = address(this).balance;
        uint256 snapshot = _snapshots[address(0)];
        profit = current > snapshot ? current - snapshot : 0;
    }

    /// @notice Get the snapshot value for a token
    function _getSnapshot(address token) internal view returns (uint256) {
        return _snapshots[token];
    }

    /// @notice Calculate change since snapshot (can be negative)
    function _changeSince(address token) internal view returns (int256) {
        uint256 current = IERC20(token).balanceOf(address(this));
        uint256 snapshot = _snapshots[token];
        return int256(current) - int256(snapshot);
    }

    // ============ Approval Utilities ============

    /// @notice Approve spender for exact amount
    function _approve(address token, address spender, uint256 amount) internal {
        bool success = IERC20(token).approve(spender, amount);
        if (!success) revert ApprovalFailed();
    }

    /// @notice Approve spender for max amount
    function _approveMax(address token, address spender) internal {
        _approve(token, spender, MAX_UINT256);
    }

    /// @notice Approve multiple tokens to same spender
    function _approveMultiple(address[] memory tokens, address spender) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            _approveMax(tokens[i], spender);
        }
    }

    /// @notice Approve if current allowance is insufficient
    function _ensureApproval(address token, address spender, uint256 amount) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (allowance < amount) {
            // Reset to 0 first (required by some tokens like USDT)
            if (allowance > 0) {
                IERC20(token).approve(spender, 0);
            }
            _approveMax(token, spender);
        }
    }

    /// @notice Revoke approval
    function _revokeApproval(address token, address spender) internal {
        IERC20(token).approve(spender, 0);
    }

    // ============ Transfer Utilities ============

    /// @notice Transfer tokens from this contract
    function _transfer(address token, address to, uint256 amount) internal {
        bool success = IERC20(token).transfer(to, amount);
        if (!success) revert TransferFailed();
    }

    /// @notice Transfer entire token balance to recipient
    function _transferAll(address token, address to) internal returns (uint256 amount) {
        amount = IERC20(token).balanceOf(address(this));
        if (amount > 0) {
            _transfer(token, to, amount);
        }
    }

    /// @notice Transfer tokens using transferFrom
    function _transferFrom(address token, address from, address to, uint256 amount) internal {
        bool success = IERC20(token).transferFrom(from, to, amount);
        if (!success) revert TransferFailed();
    }

    /// @notice Transfer ETH
    function _transferETH(address to, uint256 amount) internal {
        (bool success,) = payable(to).call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Transfer all ETH balance
    function _transferAllETH(address to) internal returns (uint256 amount) {
        amount = address(this).balance;
        if (amount > 0) {
            _transferETH(to, amount);
        }
    }

    // ============ WETH Utilities ============

    /// @notice Wrap ETH to WETH
    function _wrapETH(uint256 amount) internal {
        IWETH(weth).deposit{value: amount}();
    }

    /// @notice Unwrap WETH to ETH
    function _unwrapETH(uint256 amount) internal {
        IWETH(weth).withdraw(amount);
    }

    /// @notice Wrap all ETH balance
    function _wrapAllETH() internal returns (uint256 amount) {
        amount = address(this).balance;
        if (amount > 0) {
            _wrapETH(amount);
        }
    }

    /// @notice Unwrap all WETH balance
    function _unwrapAllWETH() internal returns (uint256 amount) {
        amount = IWETH(weth).balanceOf(address(this));
        if (amount > 0) {
            _unwrapETH(amount);
        }
    }

    // ============ Rescue Functions ============

    /// @notice Rescue stuck tokens to specified address
    function _rescueTokens(address token, address to) internal returns (uint256 amount) {
        amount = _transferAll(token, to);
    }

    /// @notice Rescue stuck ETH to specified address
    function _rescueETH(address to) internal returns (uint256 amount) {
        amount = _transferAllETH(to);
    }

    /// @notice Rescue multiple tokens
    function _rescueMultiple(address[] memory tokens, address to) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            _transferAll(tokens[i], to);
        }
    }

    // ============ Token Info ============

    /// @notice Get token decimals (with fallback to 18)
    function _decimals(address token) internal view returns (uint8) {
        try IERC20(token).decimals() returns (uint8 dec) {
            return dec;
        } catch {
            return 18;
        }
    }

    /// @notice Convert amount to token's decimal precision
    function _toTokenAmount(address token, uint256 amount) internal view returns (uint256) {
        uint8 dec = _decimals(token);
        if (dec == 18) return amount;
        if (dec < 18) return amount / (10 ** (18 - dec));
        return amount * (10 ** (dec - 18));
    }

    /// @notice Normalize amount to 18 decimals
    function _toWei(address token, uint256 amount) internal view returns (uint256) {
        uint8 dec = _decimals(token);
        if (dec == 18) return amount;
        if (dec < 18) return amount * (10 ** (18 - dec));
        return amount / (10 ** (dec - 18));
    }
}

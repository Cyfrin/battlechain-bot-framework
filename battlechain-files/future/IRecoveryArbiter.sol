// SPDX-License-Identifier: MIT
// aderyn-ignore-next-line(unspecific-solidity-pragma,push-zero-opcode)
pragma solidity ^0.8.24;

/// @title IRecoveryArbiter
/// @notice Interface for the RecoveryArbiter contract that serves as a default recovery address
/// for BattleChain Safe Harbor agreements.
interface IRecoveryArbiter {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when ETH is recovered and sent to a recipient
    /// @param agreement The agreement contract address associated with the recovery
    /// @param recipient The address receiving the recovered funds
    /// @param amount The amount of ETH transferred
    /// @param reason A description of the recovery reason
    event ETHRecovered(address indexed agreement, address indexed recipient, uint256 amount, string reason);

    /// @notice Emitted when ERC20 tokens are recovered and sent to a recipient
    /// @param agreement The agreement contract address associated with the recovery
    /// @param token The ERC20 token contract address
    /// @param recipient The address receiving the recovered tokens
    /// @param amount The amount of tokens transferred
    /// @param reason A description of the recovery reason
    event ERC20Recovered(
        address indexed agreement, address indexed token, address indexed recipient, uint256 amount, string reason
    );

    /// @notice Emitted when an arbitrary call is executed
    /// @param agreement The agreement contract address associated with the call
    /// @param target The target contract address
    /// @param value The ETH value sent with the call
    /// @param data The calldata sent
    /// @param reason A description of the call reason
    event ArbitraryCallExecuted(
        address indexed agreement, address indexed target, uint256 value, bytes data, string reason
    );

    /// @notice Emitted when an arbiter is added
    /// @param arbiter The address granted arbiter role
    event ArbiterAdded(address indexed arbiter);

    /// @notice Emitted when an arbiter is removed
    /// @param arbiter The address revoked from arbiter role
    event ArbiterRemoved(address indexed arbiter);

    /// @notice Emitted when ETH is received
    /// @param sender The address that sent the ETH
    /// @param amount The amount of ETH received
    event ETHReceived(address indexed sender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                  OWNER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Adds an arbiter
    /// @param arbiter The address to grant arbiter role
    function addArbiter(address arbiter) external;

    /// @notice Removes an arbiter
    /// @param arbiter The address to revoke arbiter role
    function removeArbiter(address arbiter) external;

    /*//////////////////////////////////////////////////////////////
                  ARBITER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Recovers ETH to a recipient
    /// @param agreement The agreement contract address associated with this recovery
    /// @param recipient The address to receive the ETH
    /// @param amount The amount of ETH to transfer
    /// @param reason A description of the recovery reason
    function recoverEth(address agreement, address payable recipient, uint256 amount, string calldata reason) external;

    /// @notice Recovers ERC20 tokens to a recipient
    /// @param agreement The agreement contract address associated with this recovery
    /// @param token The ERC20 token contract address
    /// @param recipient The address to receive the tokens
    /// @param amount The amount of tokens to transfer
    /// @param reason A description of the recovery reason
    function recoverErc20(
        address agreement,
        address token,
        address recipient,
        uint256 amount,
        string calldata reason
    )
        external;

    /// @notice Executes an arbitrary call (for recovering other token types or special cases)
    /// @param agreement The agreement contract address associated with this call
    /// @param target The target contract address
    /// @param value The ETH value to send with the call
    /// @param data The calldata to send
    /// @param reason A description of the call reason
    function executeCall(
        address agreement,
        address target,
        uint256 value,
        bytes calldata data,
        string calldata reason
    )
        external
        returns (bytes memory);

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Checks if an address is an arbiter
    /// @param account The address to check
    /// @return True if the address is an arbiter
    function isArbiter(address account) external view returns (bool);
}

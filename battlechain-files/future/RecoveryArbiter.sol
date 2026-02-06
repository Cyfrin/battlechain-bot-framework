// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Work in progress.
// This contract will be able to govern the payouts of recovered funds, so that whitehats don't have
// to trust protocols to honor their agreements
// However, we are blocked by BattleChain having Chainlink price feeds in order to make sure the caps and floors are
// respected.
contract RecoveryArbiter { }

// import { IRecoveryArbiter } from "src/interface/IRecoveryArbiter.sol";
// import {
//     Ownable2StepUpgradeable,
//     OwnableUpgradeable
// } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// /// @title RecoveryArbiter
// /// @notice A contract that serves as a default recovery address for BattleChain Safe Harbor agreements.
// /// @dev This contract holds recovered funds and allows arbiters (DAO/multisig) to resolve disputes
// /// and distribute funds to the appropriate parties.
// // aderyn-ignore-next-line(centralization-risk)
// contract RecoveryArbiter is IRecoveryArbiter, Ownable2StepUpgradeable {
//     using SafeERC20 for IERC20;

//     /*//////////////////////////////////////////////////////////////
//                                  ERRORS
//     //////////////////////////////////////////////////////////////*/
//     error RecoveryArbiter__NotArbiter();
//     error RecoveryArbiter__ArbiterAlreadyExists();
//     error RecoveryArbiter__ArbiterDoesNotExist();
//     error RecoveryArbiter__ETHTransferFailed();
//     error RecoveryArbiter__ArbitraryCallFailed();
//     error RecoveryArbiter__ZeroAddress();

//     /*//////////////////////////////////////////////////////////////
//                             STATE VARIABLES
//     //////////////////////////////////////////////////////////////*/
//     /// @notice Mapping of addresses that have the arbiter role
//     mapping(address => bool) private s_arbiters;

//     /*//////////////////////////////////////////////////////////////
//                                MODIFIERS
//     //////////////////////////////////////////////////////////////*/
//     /// @notice Restricts function access to arbiters only
//     modifier onlyArbiter() {
//         if (!s_arbiters[msg.sender]) {
//             revert RecoveryArbiter__NotArbiter();
//         }
//         _;
//     }

//     /*//////////////////////////////////////////////////////////////
//                               INITIALIZER
//     //////////////////////////////////////////////////////////////*/
//     constructor() {
//         _disableInitializers();
//     }

//     function initialize(address initialOwner) external initializer {
//         __Ownable_init_unchained(initialOwner);
//     }

//     /*//////////////////////////////////////////////////////////////
//                             RECEIVE/FALLBACK
//     //////////////////////////////////////////////////////////////*/
//     receive() external payable {
//         _fallback();
//     }

//     fallback() external payable {
//         _fallback();
//     }

//     function _fallback() internal {
//         if (msg.value > 0) {
//             emit ETHReceived(msg.sender, msg.value);
//         }
//     }

//     /*//////////////////////////////////////////////////////////////
//               OWNER-FACING STATE-CHANGING FUNCTIONS
//     //////////////////////////////////////////////////////////////*/
//     /// @notice Adds an arbiter
//     /// @param arbiter The address to grant arbiter role
//     // aderyn-ignore-next-line(centralization-risk)
//     function addArbiter(address arbiter) external onlyOwner {
//         if (arbiter == address(0)) {
//             revert RecoveryArbiter__ZeroAddress();
//         }
//         if (s_arbiters[arbiter]) {
//             revert RecoveryArbiter__ArbiterAlreadyExists();
//         }
//         emit ArbiterAdded(arbiter);
//         s_arbiters[arbiter] = true;
//     }

//     /// @notice Removes an arbiter
//     /// @param arbiter The address to revoke arbiter role
//     // aderyn-ignore-next-line(centralization-risk)
//     function removeArbiter(address arbiter) external onlyOwner {
//         if (!s_arbiters[arbiter]) {
//             revert RecoveryArbiter__ArbiterDoesNotExist();
//         }
//         emit ArbiterRemoved(arbiter);
//         s_arbiters[arbiter] = false;
//     }

//     /*//////////////////////////////////////////////////////////////
//               ARBITER-FACING STATE-CHANGING FUNCTIONS
//     //////////////////////////////////////////////////////////////*/
//     /// @notice Recovers ETH to a recipient
//     /// @param agreement The agreement contract address associated with this recovery
//     /// @param recipient The address to receive the ETH
//     /// @param amount The amount of ETH to transfer
//     /// @param reason A description of the recovery reason
//     function recoverETH(
//         address agreement,
//         address payable recipient,
//         uint256 amount,
//         string calldata reason
//     )
//         external
//         onlyArbiter
//     {
//         if (recipient == address(0)) {
//             revert RecoveryArbiter__ZeroAddress();
//         }

//         (bool success,) = recipient.call{ value: amount }("");
//         if (!success) {
//             revert RecoveryArbiter__ETHTransferFailed();
//         }

//         emit ETHRecovered(agreement, recipient, amount, reason);
//     }

//     /// @notice Recovers ERC20 tokens to a recipient
//     /// @param agreement The agreement contract address associated with this recovery
//     /// @param token The ERC20 token contract address
//     /// @param recipient The address to receive the tokens
//     /// @param amount The amount of tokens to transfer
//     /// @param reason A description of the recovery reason
//     function recoverERC20(
//         address agreement,
//         address token,
//         address recipient,
//         uint256 amount,
//         string calldata reason
//     )
//         external
//         onlyArbiter
//     {
//         if (recipient == address(0)) {
//             revert RecoveryArbiter__ZeroAddress();
//         }
//         if (token == address(0)) {
//             revert RecoveryArbiter__ZeroAddress();
//         }

//         IERC20(token).safeTransfer(recipient, amount);

//         emit ERC20Recovered(agreement, token, recipient, amount, reason);
//     }

//     /// @notice Executes an arbitrary call (for recovering other token types or special cases)
//     /// @param agreement The agreement contract address associated with this call
//     /// @param target The target contract address
//     /// @param value The ETH value to send with the call
//     /// @param data The calldata to send
//     /// @param reason A description of the call reason
//     function executeCall(
//         address agreement,
//         address target,
//         uint256 value,
//         bytes calldata data,
//         string calldata reason
//     )
//         external
//         onlyArbiter
//         returns (bytes memory)
//     {
//         if (target == address(0)) {
//             revert RecoveryArbiter__ZeroAddress();
//         }

//         (bool success, bytes memory returnData) = target.call{ value: value }(data);
//         if (!success) {
//             revert RecoveryArbiter__ArbitraryCallFailed();
//         }

//         emit ArbitraryCallExecuted(agreement, target, value, data, reason);

//         return returnData;
//     }

//     /*//////////////////////////////////////////////////////////////
//                     USER-FACING READ-ONLY FUNCTIONS
//     //////////////////////////////////////////////////////////////*/
//     /// @notice Checks if an address is an arbiter
//     /// @param account The address to check
//     /// @return True if the address is an arbiter
//     function isArbiter(address account) external view returns (bool) {
//         return s_arbiters[account];
//     }
// }

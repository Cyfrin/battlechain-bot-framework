// SPDX-License-Identifier: MIT
// aderyn-ignore-next-line(unspecific-solidity-pragma,push-zero-opcode)
pragma solidity ^0.8.24;

import {
    AgreementDetails,
    BountyTerms,
    Contact,
    Chain,
    Account
} from "../types/AgreementTypes.sol";

/// @title IAgreement
/// @notice Interface for the BattleChain Safe Harbor Agreement contract
interface IAgreement {
    /*//////////////////////////////////////////////////////////////
                    OWNER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Extend the commitment window
    /// @dev Can only extend, never shorten while active
    /// @param newCantChangeUntil The new commitment window end timestamp
    function extendCommitmentWindow(uint256 newCantChangeUntil) external;

    /// @notice Set the protocol name
    function setProtocolName(string memory protocolName) external;

    /// @notice Set the agreement contact details
    function setContactDetails(Contact[] memory contactDetails) external;

    /// @notice Add or update chains in the agreement
    function addOrSetChains(Chain[] memory chains) external;

    /// @notice Remove chains from the agreement
    function removeChains(string[] memory caip2ChainIds) external;

    /// @notice Add accounts to an existing chain
    function addAccounts(string memory caip2ChainId, Account[] memory newAccounts) external;

    /// @notice Remove accounts from a chain
    function removeAccounts(string memory caip2ChainId, string[] memory accountAddresses) external;

    /// @notice Set the bounty terms (subject to modification guards during commitment)
    function setBountyTerms(BountyTerms memory bountyTerms) external;

    /// @notice Set the agreement URI
    function setAgreementURI(string memory agreementURI) external;

    /*//////////////////////////////////////////////////////////////
                        USER READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Check if a contract address is in the agreement's scope for the current chain
    /// @param contractAddress The contract address to check (native EVM address)
    /// @return True if the contract is in scope for this agreement on BattleChain
    function isContractInScope(address contractAddress) external view returns (bool);

    /// @notice Get the commitment window end timestamp
    /// @return The timestamp until which terms cannot be changed unfavorably
    function getCantChangeUntil() external view returns (uint256);

    /// @notice Get the full agreement details
    function getDetails() external view returns (AgreementDetails memory);

    /// @notice Get the protocol name
    function getProtocolName() external view returns (string memory);

    /// @notice Get the bounty terms
    function getBountyTerms() external view returns (BountyTerms memory);

    /// @notice Get the agreement URI
    function getAgreementURI() external view returns (string memory);

    /// @notice Get the registry address
    function getRegistry() external view returns (address);

    /// @notice Get all chain IDs covered by this agreement
    function getChainIds() external view returns (string[] memory);

    /// @notice Get the BattleChain CAIP-2 chain ID
    function getBattleChainCaip2ChainId() external view returns (string memory);

    /// @notice Get all BattleChain scope addresses (native addresses)
    /// @dev Used by AttackRegistry for bulk operations
    function getBattleChainScopeAddresses() external view returns (address[] memory);

    /// @notice Get the count of BattleChain scope addresses
    function getBattleChainScopeCount() external view returns (uint256);

    /// @notice Get the owner of the agreement (from Ownable)
    function owner() external view returns (address);
}
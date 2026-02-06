// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


/// @title IAgreement
/// @notice Interface for the BattleChain Safe Harbor Agreement contract
interface IAgreement {

        // @notice Struct that contains the details of the agreement.
    struct AgreementDetails {
        // The name of the protocol adopting the agreement.
        string protocolName;
        // The contact details (required for pre-notifying).
        Contact[] contactDetails;
        // The scope and recovery address by chain.
        // Covers both Urgent Blackhat Exploit and BattleChain Under Attack coverage.
        Chain[] chains;
        // The terms of the agreement.
        BountyTerms bountyTerms;
        // URI of the actual agreement document, which confirms all terms.
        // This should be a permanent URI (e.g. IPFS with Arweave persistance, base64, caip:, etc.)
        string agreementURI;
    }

    /// @notice Struct that contains the contact details of the agreement.
    struct Contact {
        string name;
        // This person's contact details (email, phone, telegram handle, etc.)
        string contact;
    }

    /// @notice Struct that contains the details of an agreement by chain.
    struct Chain {
        // The address to which recovered assets will be sent.
        // Please default to a BattleChain address
        string assetRecoveryAddress;
        // The accounts in scope for the agreement.
        Account[] accounts;
        // The CAIP-2 chain ID. Please refer to the CAIP-2 standard for more details.
        // https://github.com/ChainAgnostic/CAIPs/blob/main/CAIPs/caip-2.md
        string caip2ChainId;
    }

    /// @notice Struct that contains the details of an account in an agreement.
    struct Account {
        // The address of the account (EOA or smart contract).
        string accountAddress;
        // The scope of child contracts included in the agreement.
        ChildContractScope childContractScope;
    }

    /// @notice Enum that defines the inclusion of child contracts in an agreement.
    enum ChildContractScope {
        // No child contracts are included.
        None,
        // Only child contracts that were created before the time of this agreement are included.
        ExistingOnly,
        // All child contracts, both existing and new, are included.
        All,
        // Only child contracts that were created after the time of this agreement are included.
        FutureOnly
    }

    /// @notice Struct that contains the terms of the bounty for the agreement.
    struct BountyTerms {
        // Percentage of the recovered funds a Whitehat receives as their bounty (0-100).
        uint256 bountyPercentage;
        // The maximum bounty in USD.
        uint256 bountyCapUsd;
        // Whether the whitehat can retain their bounty or must return all funds to
        // the asset recovery address.
        bool retainable;
        // The identity verification requirements on the whitehat.
        IdentityRequirements identity;
        // The diligence requirements placed on eligible whitehats. Only applicable for Named whitehats.
        string diligenceRequirements;
        // Optional. Caps the total USD value of bounties paid across all whitehats for a single exploit.
        // If set to 0, no aggregate cap applies and each whitehat may receive up to bountyCapUsd individually.
        uint256 aggregateBountyCapUsd;
    }

    /// @notice Whitehat identity verification requirements.
    enum IdentityRequirements {
        // The whitehat will be subject to no KYC requirements.
        Anonymous,
        // The whitehat must provide a pseudonym.
        Pseudonymous,
        // The whitehat must confirm their legal name.
        Named
    }
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

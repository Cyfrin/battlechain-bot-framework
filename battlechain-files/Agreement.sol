// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AgreementDetails, Account, Chain, Contact, BountyTerms } from "./types/AgreementTypes.sol";
import { IBattleChainSafeHarborRegistry } from "./interface/IBattleChainSafeHarborRegistry.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev
 * This contract is Ownable and mutable. It is intended to be used by entities adopting the
 * Safe Harbor agreement that either need to frequently update their terms, have too many terms to
 * fit in a single transaction, or wish to delegate the management of their agreement to a different
 * address than the deployer.
 */
// aderyn-ignore-next-line(centralization-risk)
contract Agreement is Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error Agreement__CannotSetBothAggregateBountyCapUsdAndRetainable();
    error Agreement__ChainNotFoundByCaip2Id(string caip2ChainId);
    error Agreement__DuplicateChainId(string caip2ChainId);
    error Agreement__InvalidChainId(string caip2ChainId);
    error Agreement__ZeroAccountsForChainId(string caip2ChainId);
    error Agreement__ChainIdHasZeroLength();
    error Agreement__InvalidAssetRecoveryAddress(string caip2ChainId);
    error Agreement__ZeroAddress();
    error Agreement__AccountNotFoundByAddress(string caip2ChainId, string accountAddress);
    error Agreement__CannotShortenCommitmentWindow(uint256 current, uint256 proposed);
    error Agreement__UnfavorableBountyChange();
    error Agreement__InvalidAddressLength();
    error Agreement__BountyPercentageExceedsMax(uint256 bountyPercentage);
    error Agreement__AggregateBountyCapBelowIndividualCap(uint256 aggregateCap, uint256 individualCap);
    error Agreement__CannotRemoveAllAccounts(string caip2ChainId);
    error Agreement__CannotReduceScopeDuringCommitment();
    error Agreement__CannotChangeAgreementURIDuringCommitment();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 private constant _DUPLICATE_CHECK_SLOT = keccak256("Agreement.duplicateChainIdCheck");
    string public constant VERSION = "1.0.0";

    IBattleChainSafeHarborRegistry private immutable REGISTRY;

    // aderyn-ignore-next-line(state-variable-could-be-immutable)
    string private s_battleChainCaip2ChainId;
    string private s_protocolName;
    Contact[] private s_contactDetails;
    BountyTerms private s_bountyTerms;
    string private s_agreementURI;

    /// @dev Commitment window end timestamp - terms cannot be changed unfavorably until this time
    uint256 private s_cantChangeUntil;

    // Chain scope - covers both Urgent Blackhat Exploit and BattleChain Under Attack
    // https://github.com/ChainAgnostic/CAIPs/blob/main/CAIPs/caip-2.md
    string[] private s_chainIds;
    mapping(string caip2ChainId => string assetRecoveryAddress) private s_assetRecoveryAddresses;
    mapping(string caip2ChainId => Account[]) private s_accounts;

    // BattleChain scope cache - native addresses for efficient AttackRegistry integration
    // This cache is maintained automatically when accounts are added/removed for the BattleChain chain
    address[] private s_battleChainScopeAddresses;
    mapping(address => bool) private s_battleChainScopeExists;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ProtocolNameUpdated(string newName);
    event BattleChainSafeHarborRegistryUpdated(address indexed newRegistry);
    event ContactDetailsSet(Contact[] newContactDetails);
    event ChainAddedOrSet(string caip2ChainId, string assetRecoveryAddress, Account[] accounts);
    event ChainRemoved(string caip2ChainId);
    event AccountAdded(string caip2ChainId, Account account);
    event AccountRemoved(string caip2ChainId, string accountAddress);
    event BountyTermsUpdated(BountyTerms newBountyTerms);
    event AgreementURIUpdated(string newAgreementURI);
    event CommitmentWindowExtended(uint256 newCantChangeUntil);
    event BattleChainScopeAddressAdded(address indexed addr);
    event BattleChainScopeAddressRemoved(address indexed addr);
    event BattleChainScopeCleared();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @notice Constructor that sets the details of the agreement.
    /// @param registry The BattleChain Safe Harbor Registry address
    /// @param owner The owner of this agreement
    /// @param battleChainCaip2ChainId The CAIP-2 chain ID for BattleChain (e.g., "eip155:626")
    /// @param details The agreement details (bounty terms, chains, contacts, etc.)
    constructor(
        address registry,
        address owner,
        string memory battleChainCaip2ChainId,
        AgreementDetails memory details
    )
        Ownable(owner)
    {
        if (registry == address(0)) {
            revert Agreement__ZeroAddress();
        }
        emit BattleChainSafeHarborRegistryUpdated(registry);
        REGISTRY = IBattleChainSafeHarborRegistry(registry);
        // @audit: This should be immutable but Solidity does not support immutable strings yet
        s_battleChainCaip2ChainId = battleChainCaip2ChainId;

        _validateBountyTerms(details.bountyTerms);
        _validateChainsAndCheckDuplicates(details.chains);
        _setDetails(details);
    }

    /*//////////////////////////////////////////////////////////////
              OWNER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Function that sets the protocol name
    // aderyn-ignore-next-line(centralization-risk)
    function setProtocolName(string calldata protocolName) external onlyOwner {
        emit ProtocolNameUpdated(protocolName);
        s_protocolName = protocolName;
    }

    /// @notice Function that sets the agreement contact details.
    // aderyn-ignore-next-line(centralization-risk)
    function setContactDetails(Contact[] memory contactDetails) external onlyOwner {
        delete s_contactDetails;
        // aderyn-ignore-next-line(costly-loop,uninitialized-local-variable)
        for (uint256 i; i < contactDetails.length; i++) {
            s_contactDetails.push(contactDetails[i]);
        }
        emit ContactDetailsSet(s_contactDetails);
    }

    /// @notice Adds or updates chains in the agreement
    /// @dev During commitment window, replacing existing chains is blocked (unfavorable to whitehats)
    // aderyn-ignore-next-line(centralization-risk)
    function addOrSetChains(Chain[] memory chains) external onlyOwner {
        _validateChainsAndCheckDuplicates(chains);
        bool inCommitmentWindow = block.timestamp < s_cantChangeUntil;

        // aderyn-ignore-next-line(costly-loop,require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < chains.length; ++i) {
            string memory chainId = chains[i].caip2ChainId;
            bool isBattleChain = _isBattleChainId(chainId);
            bool chainExists = _chainExists(chainId);

            // During commitment window, cannot replace existing chains (could reduce scope)
            if (inCommitmentWindow && chainExists) {
                revert Agreement__CannotReduceScopeDuringCommitment();
            }

            if (!chainExists) {
                s_chainIds.push(chainId);
            } else if (isBattleChain) {
                // Clear existing cache when replacing BattleChain accounts
                _clearBattleChainScope();
            }

            s_assetRecoveryAddresses[chainId] = chains[i].assetRecoveryAddress;
            delete s_accounts[chainId];
            // aderyn-ignore-next-line(costly-loop,require-revert-in-loop,uninitialized-local-variable)
            for (uint256 j; j < chains[i].accounts.length; ++j) {
                s_accounts[chainId].push(chains[i].accounts[j]);
                // Maintain BattleChain scope cache
                if (isBattleChain) {
                    _addToBattleChainScope(chains[i].accounts[j].accountAddress);
                }
            }
            emit ChainAddedOrSet(chainId, chains[i].assetRecoveryAddress, chains[i].accounts);
        }
    }

    /// @notice Removes chains by CAIP-2 IDs
    /// @dev Blocked during commitment window (unfavorable to whitehats)
    // aderyn-ignore-next-line(centralization-risk)
    function removeChains(string[] memory caip2ChainIds) external onlyOwner {
        // Cannot remove chains during commitment window
        if (block.timestamp < s_cantChangeUntil) {
            revert Agreement__CannotReduceScopeDuringCommitment();
        }

        // aderyn-ignore-next-line(costly-loop,require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < caip2ChainIds.length; ++i) {
            string memory chainId = caip2ChainIds[i];
            uint256 idx = _findChainIndex(chainId);

            // Clear BattleChain scope cache if removing BattleChain
            if (_isBattleChainId(chainId)) {
                _clearBattleChainScope();
            }

            delete s_assetRecoveryAddresses[chainId];
            delete s_accounts[chainId];
            uint256 lastIdx = s_chainIds.length - 1;
            if (idx != lastIdx) {
                s_chainIds[idx] = s_chainIds[lastIdx];
            }
            s_chainIds.pop();
            emit ChainRemoved(chainId);
        }
    }

    /// @notice Adds accounts to an existing chain
    /// @param caip2ChainId The CAIP-2 ID of the chain
    /// @param newAccounts Array of accounts to add
    /// @dev We do not check for duplicate accounts here for gas efficiency.
    // aderyn-ignore-next-line(centralization-risk)
    function addAccounts(string memory caip2ChainId, Account[] memory newAccounts) external onlyOwner {
        if (!_chainExists(caip2ChainId)) {
            revert Agreement__ChainNotFoundByCaip2Id(caip2ChainId);
        }
        bool isBattleChain = _isBattleChainId(caip2ChainId);
        // aderyn-ignore-next-line(costly-loop,require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < newAccounts.length; ++i) {
            s_accounts[caip2ChainId].push(newAccounts[i]);
            // Maintain BattleChain scope cache
            if (isBattleChain) {
                _addToBattleChainScope(newAccounts[i].accountAddress);
            }
            emit AccountAdded(caip2ChainId, newAccounts[i]);
        }
    }

    /// @notice Removes accounts from a chain by address
    /// @param caip2ChainId The CAIP-2 ID of the chain
    /// @param accountAddresses Array of account addresses to remove (case-sensitive, must match stored value exactly)
    /// @dev Blocked during commitment window (unfavorable to whitehats).
    ///      Address matching is case-sensitive - use the exact same string that was used when adding.
    // aderyn-ignore-next-line(centralization-risk)
    function removeAccounts(string memory caip2ChainId, string[] memory accountAddresses) external onlyOwner {
        // Cannot remove accounts during commitment window
        if (block.timestamp < s_cantChangeUntil) {
            revert Agreement__CannotReduceScopeDuringCommitment();
        }

        if (!_chainExists(caip2ChainId)) {
            revert Agreement__ChainNotFoundByCaip2Id(caip2ChainId);
        }
        // Ensure at least one account remains after removal
        if (accountAddresses.length >= s_accounts[caip2ChainId].length) {
            revert Agreement__CannotRemoveAllAccounts(caip2ChainId);
        }
        bool isBattleChain = _isBattleChainId(caip2ChainId);
        // aderyn-ignore-next-line(costly-loop,require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < accountAddresses.length; ++i) {
            uint256 idx = _findAccountIndex(caip2ChainId, accountAddresses[i]);
            uint256 lastIdx = s_accounts[caip2ChainId].length - 1;
            if (idx != lastIdx) {
                s_accounts[caip2ChainId][idx] = s_accounts[caip2ChainId][lastIdx];
            }
            s_accounts[caip2ChainId].pop();
            // Maintain BattleChain scope cache
            if (isBattleChain) {
                _removeFromBattleChainScope(accountAddresses[i]);
            }
            emit AccountRemoved(caip2ChainId, accountAddresses[i]);
        }
    }

    /// @notice Sets the bounty terms
    /// @dev During commitment window, only favorable changes are allowed:
    ///      - bountyPercentage can only increase
    ///      - bountyCapUsd can only increase
    ///      - aggregateBountyCapUsd can only increase
    ///      - identity requirements cannot become stricter
    // aderyn-ignore-next-line(centralization-risk)
    function setBountyTerms(BountyTerms memory bountyTerms) external onlyOwner {
        _validateBountyTerms(bountyTerms);

        // If within commitment window, enforce favorable-only changes
        if (block.timestamp < s_cantChangeUntil) {
            BountyTerms memory current = s_bountyTerms;

            // Check bounty percentage (must not decrease)
            if (bountyTerms.bountyPercentage < current.bountyPercentage) {
                revert Agreement__UnfavorableBountyChange();
            }

            // Check bounty cap (must not decrease)
            if (bountyTerms.bountyCapUsd < current.bountyCapUsd) {
                revert Agreement__UnfavorableBountyChange();
            }

            // Check aggregate bounty cap (must not decrease)
            if (bountyTerms.aggregateBountyCapUsd < current.aggregateBountyCapUsd) {
                revert Agreement__UnfavorableBountyChange();
            }

            // Check identity requirements (cannot become stricter: Anonymous < Pseudonymous < Named)
            if (uint8(bountyTerms.identity) > uint8(current.identity)) {
                revert Agreement__UnfavorableBountyChange();
            }

            // Cannot change from retainable to non-retainable
            if (current.retainable && !bountyTerms.retainable) {
                revert Agreement__UnfavorableBountyChange();
            }
        }

        emit BountyTermsUpdated(bountyTerms);
        s_bountyTerms = bountyTerms;
    }

    /// @notice Sets the agreement URI
    /// @dev Blocked during commitment window (changing URI could mislead whitehats)
    // aderyn-ignore-next-line(centralization-risk)
    function setAgreementURI(string calldata agreementURI) external onlyOwner {
        if (block.timestamp < s_cantChangeUntil) {
            revert Agreement__CannotChangeAgreementURIDuringCommitment();
        }
        emit AgreementURIUpdated(agreementURI);
        s_agreementURI = agreementURI;
    }

    /// @notice Extend the commitment window
    /// @dev Can only extend, never shorten
    /// @param newCantChangeUntil The new commitment window end timestamp
    // aderyn-ignore-next-line(centralization-risk)
    function extendCommitmentWindow(uint256 newCantChangeUntil) external onlyOwner {
        if (newCantChangeUntil <= s_cantChangeUntil) {
            revert Agreement__CannotShortenCommitmentWindow(s_cantChangeUntil, newCantChangeUntil);
        }
        emit CommitmentWindowExtended(newCantChangeUntil);
        s_cantChangeUntil = newCantChangeUntil;
    }

    /*//////////////////////////////////////////////////////////////
                   INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Adds an address to the BattleChain scope cache
    /// @param accountAddress The hex string address to add
    function _addToBattleChainScope(string memory accountAddress) internal {
        address addr = _parseAddress(accountAddress);
        if (!s_battleChainScopeExists[addr]) {
            s_battleChainScopeAddresses.push(addr);
            s_battleChainScopeExists[addr] = true;
            emit BattleChainScopeAddressAdded(addr);
        }
    }

    /// @notice Removes an address from the BattleChain scope cache
    /// @param accountAddress The hex string address to remove
    function _removeFromBattleChainScope(string memory accountAddress) internal {
        address addr = _parseAddress(accountAddress);
        if (s_battleChainScopeExists[addr]) {
            // Find and remove using swap-and-pop
            uint256 length = s_battleChainScopeAddresses.length;
            // aderyn-ignore-next-line(costly-loop,uninitialized-local-variable)
            for (uint256 i; i < length; ++i) {
                if (s_battleChainScopeAddresses[i] == addr) {
                    uint256 lastIdx = length - 1;
                    if (i != lastIdx) {
                        s_battleChainScopeAddresses[i] = s_battleChainScopeAddresses[lastIdx];
                    }
                    s_battleChainScopeAddresses.pop();
                    break;
                }
            }
            s_battleChainScopeExists[addr] = false;
            emit BattleChainScopeAddressRemoved(addr);
        }
    }

    /// @notice Clears the entire BattleChain scope cache
    function _clearBattleChainScope() internal {
        uint256 length = s_battleChainScopeAddresses.length;
        // aderyn-ignore-next-line(costly-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            s_battleChainScopeExists[s_battleChainScopeAddresses[i]] = false;
        }
        delete s_battleChainScopeAddresses;
        emit BattleChainScopeCleared();
    }

    /// @notice Internal function to validate that chains don't have duplicate CAIP-2 IDs
    function _validateChainsAndCheckDuplicates(Chain[] memory chains) internal {
        // aderyn-ignore-next-line(require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < chains.length; ++i) {
            if (bytes(chains[i].caip2ChainId).length == 0) {
                revert Agreement__ChainIdHasZeroLength();
            }
            if (!REGISTRY.isChainValid(chains[i].caip2ChainId)) {
                revert Agreement__InvalidChainId(chains[i].caip2ChainId);
            }
            if (chains[i].accounts.length == 0) {
                revert Agreement__ZeroAccountsForChainId(chains[i].caip2ChainId);
            }
            if (bytes(chains[i].assetRecoveryAddress).length == 0) {
                revert Agreement__InvalidAssetRecoveryAddress(chains[i].caip2ChainId);
            }

            bytes32 slot = _duplicateCheckSlot(chains[i].caip2ChainId);
            bool seen;
            assembly {
                seen := tload(slot)
            }
            if (seen) {
                revert Agreement__DuplicateChainId(chains[i].caip2ChainId);
            }
            assembly {
                tstore(slot, 1)
            }
        }

        // Clear the temp storage in case this is within a batched transaction
        // aderyn-ignore-next-line(uninitialized-local-variable)
        for (uint256 i; i < chains.length; ++i) {
            bytes32 slot = _duplicateCheckSlot(chains[i].caip2ChainId);
            assembly {
                tstore(slot, 0)
            }
        }
    }

    /// @notice Internal function to validate bounty terms
    function _validateBountyTerms(BountyTerms memory bountyTerms) internal pure {
        if (bountyTerms.aggregateBountyCapUsd > 0 && bountyTerms.retainable) {
            revert Agreement__CannotSetBothAggregateBountyCapUsdAndRetainable();
        }
        // Bounty percentage cannot exceed 100%
        if (bountyTerms.bountyPercentage > 100) {
            revert Agreement__BountyPercentageExceedsMax(bountyTerms.bountyPercentage);
        }
        // If aggregate cap is set, it must be >= individual cap to avoid ambiguity
        if (bountyTerms.aggregateBountyCapUsd > 0 && bountyTerms.aggregateBountyCapUsd < bountyTerms.bountyCapUsd) {
            revert Agreement__AggregateBountyCapBelowIndividualCap(
                bountyTerms.aggregateBountyCapUsd, bountyTerms.bountyCapUsd
            );
        }
    }

    /// @notice Internal function to set all agreement details with proper array copying
    /// @dev Do not call this function without validating the details first
    function _setDetails(AgreementDetails memory details) internal {
        s_protocolName = details.protocolName;
        s_agreementURI = details.agreementURI;
        s_bountyTerms = details.bountyTerms;

        // Copy contact details
        delete s_contactDetails;
        // aderyn-ignore-next-line(costly-loop,uninitialized-local-variable)
        for (uint256 i; i < details.contactDetails.length; ++i) {
            s_contactDetails.push(details.contactDetails[i]);
        }

        // Copy chains
        delete s_chainIds;
        // aderyn-ignore-next-line(costly-loop,require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < details.chains.length; ++i) {
            string memory chainId = details.chains[i].caip2ChainId;
            bool isBattleChain = _isBattleChainId(chainId);
            s_chainIds.push(chainId);
            s_assetRecoveryAddresses[chainId] = details.chains[i].assetRecoveryAddress;

            // aderyn-ignore-next-line(costly-loop,require-revert-in-loop,uninitialized-local-variable)
            for (uint256 j; j < details.chains[i].accounts.length; ++j) {
                s_accounts[chainId].push(details.chains[i].accounts[j]);
                // Populate BattleChain scope cache
                if (isBattleChain) {
                    _addToBattleChainScope(details.chains[i].accounts[j].accountAddress);
                }
            }
        }
    }

    /// @notice Checks if a chain exists
    function _chainExists(string memory caip2ChainId) internal view returns (bool) {
        bytes32 targetHash = _hashString(caip2ChainId);
        uint256 length = s_chainIds.length;
        // aderyn-ignore-next-line(uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            // aderyn-ignore-next-line(storage-array-memory-edit)
            if (_hashString(s_chainIds[i]) == targetHash) {
                return true;
            }
        }
        return false;
    }

    /// @notice Finds the index of a chain ID
    function _findChainIndex(string memory caip2ChainId) internal view returns (uint256) {
        bytes32 targetHash = _hashString(caip2ChainId);
        uint256 length = s_chainIds.length;
        // aderyn-ignore-next-line(uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            // aderyn-ignore-next-line(storage-array-memory-edit)
            if (_hashString(s_chainIds[i]) == targetHash) {
                return i;
            }
        }
        revert Agreement__ChainNotFoundByCaip2Id(caip2ChainId);
    }

    /// @notice Finds the index of an account by address within a chain
    /// @dev This comparison is CASE-SENSITIVE. When removing an account, the address string
    ///      must match exactly as it was stored (including case). For example, if an account
    ///      was added with "0xABC...", it must be removed with "0xABC...", not "0xabc...".
    ///      Note: The BattleChain scope cache uses parsed native addresses which are case-insensitive.
    /// @param caip2ChainId The CAIP-2 chain ID
    /// @param accountAddress The account address string to find (case-sensitive match)
    /// @return The index of the account in the chain's accounts array
    function _findAccountIndex(
        string memory caip2ChainId,
        string memory accountAddress
    )
        internal
        view
        returns (uint256)
    {
        bytes32 targetHash = _hashString(accountAddress);
        Account[] storage chainAccounts = s_accounts[caip2ChainId];
        uint256 length = chainAccounts.length;
        // aderyn-ignore-next-line(uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            // aderyn-ignore-next-line(storage-array-memory-edit)
            if (_hashString(chainAccounts[i].accountAddress) == targetHash) {
                return i;
            }
        }
        revert Agreement__AccountNotFoundByAddress(caip2ChainId, accountAddress);
    }

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the full agreement details
    function getDetails() external view returns (AgreementDetails memory details) {
        details.protocolName = s_protocolName;
        details.agreementURI = s_agreementURI;
        details.bountyTerms = s_bountyTerms;

        // Copy contact details
        uint256 contactsLength = s_contactDetails.length;
        details.contactDetails = new Contact[](contactsLength);
        for (uint256 i; i < contactsLength; ++i) {
            details.contactDetails[i] = s_contactDetails[i];
        }

        // Reconstruct chains
        uint256 chainsLength = s_chainIds.length;
        details.chains = new Chain[](chainsLength);
        for (uint256 i; i < chainsLength; ++i) {
            string memory chainId = s_chainIds[i];
            details.chains[i].caip2ChainId = chainId;
            details.chains[i].assetRecoveryAddress = s_assetRecoveryAddresses[chainId];

            Account[] storage accts = s_accounts[chainId];
            uint256 acctsLength = accts.length;
            details.chains[i].accounts = new Account[](acctsLength);
            for (uint256 j; j < acctsLength; ++j) {
                details.chains[i].accounts[j] = accts[j];
            }
        }
    }

    /// @notice Returns the protocol name
    function getProtocolName() external view returns (string memory) {
        return s_protocolName;
    }

    /// @notice Returns the bounty terms
    function getBountyTerms() external view returns (BountyTerms memory) {
        return s_bountyTerms;
    }

    /// @notice Returns the agreement URI
    function getAgreementURI() external view returns (string memory) {
        return s_agreementURI;
    }

    /// @notice Returns the registry address
    function getRegistry() external view returns (address) {
        return address(REGISTRY);
    }

    /// @notice Returns all chain IDs
    function getChainIds() external view returns (string[] memory) {
        return s_chainIds;
    }

    /// @notice Returns all accounts for a specific chain
    /// @param caip2ChainId The CAIP-2 chain ID to get accounts for
    /// @return accounts Array of accounts for the specified chain
    function getChainAccounts(string memory caip2ChainId) external view returns (Account[] memory accounts) {
        Account[] storage chainAccounts = s_accounts[caip2ChainId];
        uint256 length = chainAccounts.length;
        accounts = new Account[](length);
        for (uint256 i; i < length; ++i) {
            accounts[i] = chainAccounts[i];
        }
    }

    /// @notice Returns the asset recovery address for a specific chain
    /// @param caip2ChainId The CAIP-2 chain ID to get the recovery address for
    /// @return The asset recovery address for the specified chain
    function getAssetRecoveryAddress(string memory caip2ChainId) external view returns (string memory) {
        return s_assetRecoveryAddresses[caip2ChainId];
    }

    /// @notice Returns the commitment window end timestamp
    function getCantChangeUntil() external view returns (uint256) {
        return s_cantChangeUntil;
    }

    /// @notice Returns the BattleChain CAIP-2 chain ID
    function getBattleChainCaip2ChainId() external view returns (string memory) {
        return s_battleChainCaip2ChainId;
    }

    /// @notice Returns all BattleChain scope addresses (native addresses)
    /// @dev Used by AttackRegistry for bulk operations
    function getBattleChainScopeAddresses() external view returns (address[] memory) {
        return s_battleChainScopeAddresses;
    }

    /// @notice Returns the count of BattleChain scope addresses
    function getBattleChainScopeCount() external view returns (uint256) {
        return s_battleChainScopeAddresses.length;
    }

    /// @notice Check if a contract address is in the agreement's scope for BattleChain
    /// @param contractAddress The contract address to check (native EVM address)
    /// @return True if the contract is in scope for this agreement on BattleChain
    function isContractInScope(address contractAddress) external view returns (bool) {
        // O(1) lookup using the cache
        return s_battleChainScopeExists[contractAddress];
    }

    function version() external pure returns (string memory) {
        return VERSION;
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Hashes a string using inline assembly for gas efficiency
    function _hashString(string memory str) internal pure returns (bytes32 result) {
        assembly {
            result := keccak256(add(str, 0x20), mload(str))
        }
    }

    /// @notice Parses a hex string address to native address type
    /// @dev Handles with/without 0x prefix, case-insensitive
    /// @param addrStr The hex string address (e.g., "0x1234..." or "1234...")
    /// @return addr The parsed native address
    function _parseAddress(string memory addrStr) internal pure returns (address addr) {
        bytes memory addrBytes = bytes(addrStr);
        uint256 length = addrBytes.length;
        uint256 start = 0;

        // Check for 0x prefix
        if (length >= 2 && addrBytes[0] == "0" && (addrBytes[1] == "x" || addrBytes[1] == "X")) {
            start = 2;
        }

        // Validate length (must be 40 hex chars after prefix)
        if (length - start != 40) {
            revert Agreement__InvalidAddressLength();
        }

        uint160 result = 0;
        // aderyn-ignore-next-line(require-revert-in-loop,literal-instead-of-constant)
        for (uint256 i = start; i < length; ++i) {
            result *= 16;
            uint8 b = uint8(addrBytes[i]);

            // ASCII: '0'=48, '9'=57, 'A'=65, 'F'=70, 'a'=97, 'f'=102
            // aderyn-ignore-next-line(literal-instead-of-constant)
            if (b >= 48 && b <= 57) {
                // '0' - '9'
                // aderyn-ignore-next-line(literal-instead-of-constant)
                result += b - 48;
            } else if (b >= 65 && b <= 70) {
                // 'A' - 'F'
                result += b - 55;
            } else if (b >= 97 && b <= 102) {
                // 'a' - 'f'
                result += b - 87;
            } else {
                revert Agreement__InvalidAddressLength();
            }
        }

        addr = address(result);
    }

    /// @notice Computes the transient storage slot for duplicate chain ID checking
    function _duplicateCheckSlot(string memory chainId) internal pure returns (bytes32 result) {
        bytes32 slot = _DUPLICATE_CHECK_SLOT;
        bytes32 chainIdHash = _hashString(chainId);
        assembly {
            mstore(0x00, slot)
            mstore(0x20, chainIdHash)
            result := keccak256(0x00, 0x40)
        }
    }

    /// @notice Checks if a chain ID matches the BattleChain chain ID
    function _isBattleChainId(string memory chainId) internal view returns (bool) {
        // aderyn-ignore-next-line(storage-array-memory-edit)
        return _hashString(chainId) == _hashString(s_battleChainCaip2ChainId);
    }
}
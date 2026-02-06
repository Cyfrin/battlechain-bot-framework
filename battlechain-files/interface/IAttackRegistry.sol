// SPDX-License-Identifier: MIT
// aderyn-ignore-next-line(unspecific-solidity-pragma,push-zero-opcode)
pragma solidity ^0.8.23;

/// @title IAttackRegistry
/// @notice Interface for the BattleChain AttackRegistry contract
interface IAttackRegistry {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    enum ContractState {
        NOT_DEPLOYED,
        NEW_DEPLOYMENT,
        ATTACK_REQUESTED,
        UNDER_ATTACK,
        PROMOTION_REQUESTED,
        PRODUCTION,
        CORRUPTED
    }

    struct AgreementInfo {
        address attackModerator; // Who can manage this agreement's attack status
        uint256 deadlineTimestamp; // When current timer expires
        uint256 promotionRequestedTimestamp; // When promotion was requested (0 if not requested)
        bool attackRequested; // Has attack mode been requested?
        bool attackApproved; // Has the request been approved?
        bool promoted; // Terminal flag - promoted to production
        bool corrupted; // Terminal flag - attack succeeded
        bool isRegistered; // Whether the agreement has been registered
    }

    /*//////////////////////////////////////////////////////////////
              DEPLOYER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Called by BattleChainDeployer when a new contract is deployed
    /// @dev Records who deployed the contract. Deployer is automatically authorized.
    function registerDeployment(address contractAddress, address deployer) external;

    /// @notice Authorize an address to request attack mode for a contract
    /// @dev Only the current authorized owner can transfer authority.
    function authorizeAgreementOwner(address contractAddress, address newOwner) external;

    /*//////////////////////////////////////////////////////////////
              ATTACK MODERATOR STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Transfer attack moderator role to a new address for an agreement
    function transferAttackModerator(address agreementAddress, address newModerator) external;

    /// @notice Request attack mode for all contracts in an agreement's BattleChain scope
    /// @dev Only for contracts deployed via BattleChainDeployer (NEW_DEPLOYMENT state)
    function requestUnderAttack(address agreementAddress) external;

    /// @notice Request attack mode for externally deployed contracts (NOT_DEPLOYED state)
    /// @dev For contracts not deployed via BattleChainDeployer. DAO will perform extra due diligence.
    function requestUnderAttackByNonAuthorized(address agreementAddress) external;

    /// @notice Skip attack mode and go directly to production
    /// @dev For protocols that don't want the attack phase. Must be deployed via BattleChainDeployer.
    function goToProduction(address agreementAddress) external;

    /// @notice Request promotion to production for all contracts in agreement (3-day delay)
    function promote(address agreementAddress) external;

    /// @notice Cancel a pending promotion for all contracts in agreement, returning to UNDER_ATTACK state
    function cancelPromotion(address agreementAddress) external;

    /// @notice Mark all contracts in agreement as corrupted after successful attack
    function markCorrupted(address agreementAddress) external;

    /*//////////////////////////////////////////////////////////////
            REGISTRY MODERATOR STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice DAO approves all contracts in agreement to enter attack mode
    function approveAttack(address agreementAddress) external;

    /// @notice DAO rejects attack request for all contracts in agreement
    function rejectAttackRequest(address agreementAddress) external;

    /// @notice DAO instantly promotes all contracts in agreement to production
    function instantPromote(address agreementAddress) external;

    /*//////////////////////////////////////////////////////////////
                    OWNER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Change the registry moderator address
    function changeRegistryModerator(address newModerator) external;

    /// @notice Change the safe harbor registry address
    function setSafeHarborRegistry(address newRegistry) external;

    /*//////////////////////////////////////////////////////////////
                        USER READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Check if a top-level contract is currently under attack (attackable)
    /// @dev Looks up the contract's agreement and checks its state
    /// @return True if the contract's agreement is in UNDER_ATTACK or PROMOTION_REQUESTED state
    function isTopLevelContractUnderAttack(address contractAddress) external view returns (bool);

    /// @notice Get the granular state of an agreement
    function getAgreementState(address agreementAddress) external view returns (ContractState);

    /// @notice Get the attack moderator for an agreement
    function getAttackModerator(address agreementAddress) external view returns (address);

    /// @notice Get the agreement address for a contract
    function getAgreementForContract(address contractAddress) external view returns (address);

    /// @notice Get the full agreement info
    function getAgreementInfo(address agreementAddress) external view returns (AgreementInfo memory);

    /// @notice Get the registry moderator address
    function getRegistryModerator() external view returns (address);

    /// @notice Get the safe harbor registry address
    function getSafeHarborRegistry() external view returns (address);

    /// @notice Get the authorized owner for a contract
    function getAuthorizedOwner(address contractAddress) external view returns (address);
}
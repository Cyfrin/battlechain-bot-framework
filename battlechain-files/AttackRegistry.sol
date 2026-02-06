// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAttackRegistry } from "./interface/IAttackRegistry.sol";
import { IBattleChainSafeHarborRegistry } from "./interface/IBattleChainSafeHarborRegistry.sol";
import { IAgreement } from "./interface/IAgreement.sol";
import { IAgreementFactory } from "./interface/IAgreementFactory.sol";

/// @title AttackRegistry
/// @notice Tracks the attack/production status of deployed contracts on BattleChain.
/// @dev Contracts go through states: NOT_DEPLOYED/NEW_DEPLOYMENT -> ATTACK_REQUESTED -> UNDER_ATTACK -> PRODUCTION
///      NEW_DEPLOYMENT is for contracts deployed via BattleChainDeployer. NOT_DEPLOYED is for external deployments.
///      The registryModerator (DAO) can approve attacks, reject requests, and instant-promote contracts.
/// @dev Designed for use with a UUPS proxy for upgradability.
// aderyn-ignore-next-line(contract-locks-ether)
contract AttackRegistry is IAttackRegistry, Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error AttackRegistry__Unauthorized(address caller);
    error AttackRegistry__InvalidState(ContractState current);
    error AttackRegistry__InsufficientCommitment(uint256 required, uint256 actual);
    error AttackRegistry__ZeroAddress();
    error AttackRegistry__NotAgreementOwner(address caller, address owner);
    error AttackRegistry__AgreementOwnerNotAuthorized(address contractAddress, address agreementOwner);
    error AttackRegistry__EmptyContractArray();
    error AttackRegistry__InvalidAgreement(address agreementAddress);
    error AttackRegistry__NotDeployedViaBattleChainDeployer(address contractAddress);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    string public constant VERSION = "1.0.0";
    uint256 public constant PROMOTION_WINDOW = 14 days;
    uint256 public constant PROMOTION_DELAY = 3 days;
    uint256 public constant MIN_COMMITMENT = 7 days;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event AgreementStateChanged(address indexed agreementAddress, ContractState newState);
    event AttackModeratorTransferred(address indexed agreementAddress, address indexed newModerator);
    event RegistryModeratorChanged(address indexed newModerator);
    event SafeHarborRegistryChanged(address indexed newRegistry);
    event AgreementFactoryChanged(address indexed newFactory);
    event BattleChainDeployerChanged(address indexed newDeployer);
    event ContractRegistered(address indexed contractAddress, address indexed agreementAddress);
    event AgreementOwnerAuthorized(address indexed contractAddress, address indexed authorizedOwner);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev Maps agreement address to its state info
    mapping(address agreementAddress => AgreementInfo info) private s_agreementInfo;
    /// @dev Maps contract address to its agreement address (set when requestUnderAttack is called)
    mapping(address contractAddress => address agreementAddress) private s_contractToAgreement;
    /// @dev Maps contract address to who deployed it via BattleChainDeployer
    mapping(address contractAddress => address deployer) private s_contractDeployer;
    /// @dev Maps contract address to who is authorized to request attack mode (set by deployer)
    mapping(address contractAddress => address authorizedOwner) private s_authorizedOwner;
    address private s_registryModerator;
    IBattleChainSafeHarborRegistry private s_safeHarborRegistry;
    IAgreementFactory private s_agreementFactory;
    address private s_battleChainDeployer;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyAttackModerator(address agreementAddress) {
        _checkAttackModerator(agreementAddress);
        _;
    }

    modifier onlyRegistryModerator() {
        _checkRegistryModerator();
        _;
    }

    function _checkAttackModerator(address agreementAddress) internal view {
        if (msg.sender != s_agreementInfo[agreementAddress].attackModerator) {
            revert AttackRegistry__Unauthorized(msg.sender);
        }
    }

    function _checkRegistryModerator() internal view {
        if (msg.sender != s_registryModerator) {
            revert AttackRegistry__Unauthorized(msg.sender);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/
    function initialize(
        address _initialOwner,
        address _registryModerator,
        address _safeHarborRegistry,
        address _agreementFactory
    )
        external
        initializer
    {
        if (_initialOwner == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        if (_registryModerator == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        if (_safeHarborRegistry == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        if (_agreementFactory == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        __Ownable_init(_initialOwner);
        s_registryModerator = _registryModerator;
        s_safeHarborRegistry = IBattleChainSafeHarborRegistry(_safeHarborRegistry);
        s_agreementFactory = IAgreementFactory(_agreementFactory);
    }

    /*//////////////////////////////////////////////////////////////
                  DEPLOYER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Called by BattleChainDeployer when a new contract is deployed
    /// @dev Records who deployed the contract. Deployer is automatically authorized to request attack mode.
    /// @param contractAddress The address of the newly deployed contract
    /// @param deployer The address that deployed this contract
    function registerDeployment(address contractAddress, address deployer) external {
        if (msg.sender != s_battleChainDeployer) {
            revert AttackRegistry__Unauthorized(msg.sender);
        }
        emit ContractRegistered(contractAddress, address(0)); // No agreement yet
        s_contractDeployer[contractAddress] = deployer;
        // Deployer is automatically authorized until they transfer authority
        s_authorizedOwner[contractAddress] = deployer;
    }

    /// @notice Authorize an address to request attack mode for a contract
    /// @dev Only the current authorized owner can transfer authority.
    /// @param contractAddress The contract to authorize for
    /// @param newOwner The address to authorize (typically the agreement owner)
    function authorizeAgreementOwner(address contractAddress, address newOwner) external {
        address currentOwner = s_authorizedOwner[contractAddress];
        if (currentOwner == address(0)) {
            revert AttackRegistry__NotDeployedViaBattleChainDeployer(contractAddress);
        }
        if (msg.sender != currentOwner) {
            revert AttackRegistry__Unauthorized(msg.sender);
        }
        emit AgreementOwnerAuthorized(contractAddress, newOwner);
        s_authorizedOwner[contractAddress] = newOwner;
    }

    /*//////////////////////////////////////////////////////////////
              ATTACK MODERATOR STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Transfer attack moderator role to a new address for an agreement
    /// @param agreementAddress The agreement to transfer moderation for
    /// @param newModerator The new moderator address
    function transferAttackModerator(
        address agreementAddress,
        address newModerator
    )
        external
        onlyAttackModerator(agreementAddress)
    {
        if (newModerator == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        emit AttackModeratorTransferred(agreementAddress, newModerator);
        s_agreementInfo[agreementAddress].attackModerator = newModerator;
    }

    /// @notice Request attack mode for all contracts in an agreement's BattleChain scope
    /// @dev Only for contracts deployed via BattleChainDeployer. Agreement owner must be the deployer of all contracts.
    /// @param agreementAddress The safe harbor agreement
    function requestUnderAttack(address agreementAddress) external {
        (address agreementOwner, address[] memory contracts) = _validateAndPrepareAgreement(agreementAddress);

        // Validate all contracts were authorized for this agreement owner
        uint256 length = contracts.length;
        // aderyn-ignore-next-line(require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            if (s_authorizedOwner[contracts[i]] != agreementOwner) {
                revert AttackRegistry__AgreementOwnerNotAuthorized(contracts[i], agreementOwner);
            }
        }

        _registerAgreement(agreementAddress, agreementOwner, contracts);
    }

    /// @notice Request attack mode for externally deployed contracts (not via BattleChainDeployer)
    /// @dev DAO will perform extra due diligence for these requests
    /// @param agreementAddress The safe harbor agreement
    function requestUnderAttackByNonAuthorized(address agreementAddress) external {
        (address agreementOwner, address[] memory contracts) = _validateAndPrepareAgreement(agreementAddress);
        _registerAgreement(agreementAddress, agreementOwner, contracts);
    }

    /// @notice Skip attack mode and go directly to production
    /// @dev For protocols that don't want the attack phase. Must be deployed via BattleChainDeployer.
    /// @param agreementAddress The safe harbor agreement
    function goToProduction(address agreementAddress) external {
        (address agreementOwner, address[] memory contracts) = _validateAndPrepareAgreement(agreementAddress);

        // Validate all contracts were authorized for this agreement owner
        uint256 length = contracts.length;
        // aderyn-ignore-next-line(require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            if (s_authorizedOwner[contracts[i]] != agreementOwner) {
                revert AttackRegistry__AgreementOwnerNotAuthorized(contracts[i], agreementOwner);
            }
        }

        // Register and immediately promote to production
        _registerAgreementAndPromote(agreementAddress, agreementOwner, contracts);
    }

    /// @notice Request promotion to production for an agreement (3-day delay)
    /// @param agreementAddress The agreement to promote
    function promote(address agreementAddress) external onlyAttackModerator(agreementAddress) {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.UNDER_ATTACK) {
            revert AttackRegistry__InvalidState(currentState);
        }
        s_agreementInfo[agreementAddress].promotionRequestedTimestamp = block.timestamp;
        emit AgreementStateChanged(agreementAddress, ContractState.PROMOTION_REQUESTED);
    }

    /// @notice Cancel a pending promotion, returning to UNDER_ATTACK state
    /// @param agreementAddress The agreement to cancel promotion for
    function cancelPromotion(address agreementAddress) external onlyAttackModerator(agreementAddress) {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.PROMOTION_REQUESTED) {
            revert AttackRegistry__InvalidState(currentState);
        }
        s_agreementInfo[agreementAddress].promotionRequestedTimestamp = 0;
        emit AgreementStateChanged(agreementAddress, ContractState.UNDER_ATTACK);
    }

    /// @notice Mark an agreement as corrupted after successful attack
    /// @param agreementAddress The agreement to mark as corrupted
    function markCorrupted(address agreementAddress) external onlyAttackModerator(agreementAddress) {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.UNDER_ATTACK && currentState != ContractState.PROMOTION_REQUESTED) {
            revert AttackRegistry__InvalidState(currentState);
        }
        s_agreementInfo[agreementAddress].corrupted = true;
        emit AgreementStateChanged(agreementAddress, ContractState.CORRUPTED);
    }

    /*//////////////////////////////////////////////////////////////
            REGISTRY MODERATOR STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice DAO approves an agreement to enter attack mode
    /// @param agreementAddress The agreement to approve for attack mode
    function approveAttack(address agreementAddress) external onlyRegistryModerator {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.ATTACK_REQUESTED) {
            revert AttackRegistry__InvalidState(currentState);
        }
        s_agreementInfo[agreementAddress].attackApproved = true;
        emit AgreementStateChanged(agreementAddress, ContractState.UNDER_ATTACK);
    }

    /// @notice DAO rejects an attack request for an agreement
    /// @dev Clears contract mappings so they can be included in a new agreement
    /// @param agreementAddress The agreement to reject
    // aderyn-ignore-next-line(reentrancy-state-change)
    function rejectAttackRequest(address agreementAddress) external onlyRegistryModerator {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.ATTACK_REQUESTED) {
            revert AttackRegistry__InvalidState(currentState);
        }

        // Get contracts to clear their mappings
        // aderyn-ignore-next-line(reentrancy-state-change)
        IAgreement agreement = IAgreement(agreementAddress);
        // aderyn-ignore-next-line(reentrancy-state-change)
        address[] memory contracts = agreement.getBattleChainScopeAddresses();
        uint256 length = contracts.length;

        // Clear contract -> agreement mappings
        // aderyn-ignore-next-line(costly-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            delete s_contractToAgreement[contracts[i]];
        }

        // Clear the agreement info
        delete s_agreementInfo[agreementAddress];
        emit AgreementStateChanged(agreementAddress, ContractState.NOT_DEPLOYED);
    }

    /// @notice DAO instantly promotes an agreement to production
    /// @dev Useful when copycat contracts are discovered or high TVL situations
    /// @param agreementAddress The agreement to instantly promote
    function instantPromote(address agreementAddress) external onlyRegistryModerator {
        ContractState currentState = _getAgreementState(agreementAddress);
        // Allow from ATTACK_REQUESTED (skip attack entirely), UNDER_ATTACK, or PROMOTION_REQUESTED
        if (
            currentState != ContractState.ATTACK_REQUESTED && currentState != ContractState.UNDER_ATTACK
                && currentState != ContractState.PROMOTION_REQUESTED
        ) {
            revert AttackRegistry__InvalidState(currentState);
        }
        s_agreementInfo[agreementAddress].promoted = true;
        emit AgreementStateChanged(agreementAddress, ContractState.PRODUCTION);
    }

    /*//////////////////////////////////////////////////////////////
                    OWNER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // aderyn-ignore-next-line(centralization-risk)
    function changeRegistryModerator(address newModerator) external onlyOwner {
        if (newModerator == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        emit RegistryModeratorChanged(newModerator);
        s_registryModerator = newModerator;
    }

    // aderyn-ignore-next-line(centralization-risk)
    function setSafeHarborRegistry(address newRegistry) external onlyOwner {
        if (newRegistry == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        emit SafeHarborRegistryChanged(newRegistry);
        s_safeHarborRegistry = IBattleChainSafeHarborRegistry(newRegistry);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function setAgreementFactory(address newFactory) external onlyOwner {
        if (newFactory == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        emit AgreementFactoryChanged(newFactory);
        s_agreementFactory = IAgreementFactory(newFactory);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function setBattleChainDeployer(address newDeployer) external onlyOwner {
        if (newDeployer == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        emit BattleChainDeployerChanged(newDeployer);
        s_battleChainDeployer = newDeployer;
    }

    /*//////////////////////////////////////////////////////////////
                        UUPS UPGRADE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Authorizes an upgrade to a new implementation
    /// @dev Only the owner can authorize upgrades
    /// @param newImplementation The address of the new implementation
    // aderyn-ignore-next-line(empty-block,centralization-risk)
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////
                        USER READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Check if a top-level contract is currently under attack (attackable)
    /// @dev Looks up the contract's agreement and checks its state
    /// @param contractAddress The contract to check
    /// @return True if the contract's agreement is in UNDER_ATTACK or PROMOTION_REQUESTED state
    function isTopLevelContractUnderAttack(address contractAddress) external view returns (bool) {
        address agreementAddress = s_contractToAgreement[contractAddress];
        if (agreementAddress == address(0)) {
            return false;
        }
        ContractState state = _getAgreementState(agreementAddress);
        return state == ContractState.UNDER_ATTACK || state == ContractState.PROMOTION_REQUESTED;
    }

    /// @notice Get the granular state of an agreement
    /// @param agreementAddress The agreement to check
    /// @return The detailed ContractState enum value
    function getAgreementState(address agreementAddress) external view returns (ContractState) {
        return _getAgreementState(agreementAddress);
    }

    /// @notice Get the attack moderator for an agreement
    function getAttackModerator(address agreementAddress) external view returns (address) {
        return s_agreementInfo[agreementAddress].attackModerator;
    }

    /// @notice Get the agreement address for a contract
    function getAgreementForContract(address contractAddress) external view returns (address) {
        return s_contractToAgreement[contractAddress];
    }

    /// @notice Get the full agreement info
    function getAgreementInfo(address agreementAddress) external view returns (AgreementInfo memory) {
        return s_agreementInfo[agreementAddress];
    }

    /// @notice Get who deployed a contract via BattleChainDeployer
    function getContractDeployer(address contractAddress) external view returns (address) {
        return s_contractDeployer[contractAddress];
    }

    function getRegistryModerator() external view returns (address) {
        return s_registryModerator;
    }

    function getSafeHarborRegistry() external view returns (address) {
        return address(s_safeHarborRegistry);
    }

    function getAuthorizedOwner(address contractAddress) external view returns (address) {
        return s_authorizedOwner[contractAddress];
    }

    function getAgreementFactory() external view returns (address) {
        return address(s_agreementFactory);
    }

    function getBattleChainDeployer() external view returns (address) {
        return s_battleChainDeployer;
    }

    function version() external pure returns (string memory) {
        return VERSION;
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Validate agreement and prepare for registration
    /// @return agreementOwner The owner of the agreement
    /// @return contracts The contracts in the agreement's scope
    // aderyn-ignore-next-line(reentrancy-state-change)
    function _validateAndPrepareAgreement(address agreementAddress)
        internal
        view
        returns (address agreementOwner, address[] memory contracts)
    {
        // Verify agreement was created by our factory
        // aderyn-ignore-next-line(reentrancy-state-change)
        if (!s_agreementFactory.isAgreementContract(agreementAddress)) {
            revert AttackRegistry__InvalidAgreement(agreementAddress);
        }

        // Check agreement is not already registered
        if (s_agreementInfo[agreementAddress].isRegistered) {
            revert AttackRegistry__InvalidState(_getAgreementState(agreementAddress));
        }

        IAgreement agreement = IAgreement(agreementAddress);
        // aderyn-ignore-next-line(reentrancy-state-change)
        agreementOwner = agreement.owner();

        // Only the agreement owner can call this
        if (msg.sender != agreementOwner) {
            revert AttackRegistry__NotAgreementOwner(msg.sender, agreementOwner);
        }

        // Get all contracts in the agreement's BattleChain scope
        // aderyn-ignore-next-line(reentrancy-state-change)
        contracts = agreement.getBattleChainScopeAddresses();
        if (contracts.length == 0) {
            revert AttackRegistry__EmptyContractArray();
        }

        // Verify commitment window for the agreement
        // aderyn-ignore-next-line(reentrancy-state-change)
        uint256 cantChangeUntil = agreement.getCantChangeUntil();
        uint256 minRequired = block.timestamp + MIN_COMMITMENT;
        if (cantChangeUntil < minRequired) {
            revert AttackRegistry__InsufficientCommitment(minRequired, cantChangeUntil);
        }

        // Validate contracts are not already linked to another agreement
        uint256 length = contracts.length;
        // aderyn-ignore-next-line(require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            if (s_contractToAgreement[contracts[i]] != address(0)) {
                revert AttackRegistry__InvalidState(ContractState.ATTACK_REQUESTED);
            }
        }
    }

    /// @notice Register an agreement and link contracts
    function _registerAgreement(address agreementAddress, address agreementOwner, address[] memory contracts) internal {
        uint256 length = contracts.length;

        // Link all contracts to this agreement
        // aderyn-ignore-next-line(costly-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            s_contractToAgreement[contracts[i]] = agreementAddress;
            emit ContractRegistered(contracts[i], agreementAddress);
        }

        // Create agreement info
        s_agreementInfo[agreementAddress] = AgreementInfo({
            attackModerator: agreementOwner,
            deadlineTimestamp: block.timestamp + PROMOTION_WINDOW,
            promotionRequestedTimestamp: 0,
            attackRequested: true,
            attackApproved: false,
            promoted: false,
            corrupted: false,
            isRegistered: true
        });

        emit AgreementStateChanged(agreementAddress, ContractState.ATTACK_REQUESTED);
    }

    /// @dev Registers agreement and immediately promotes to production (skipping attack phase)
    function _registerAgreementAndPromote(
        address agreementAddress,
        address agreementOwner,
        address[] memory contracts
    )
        internal
    {
        uint256 length = contracts.length;

        // Link all contracts to this agreement
        // aderyn-ignore-next-line(costly-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            s_contractToAgreement[contracts[i]] = agreementAddress;
            emit ContractRegistered(contracts[i], agreementAddress);
        }

        // Create agreement info - directly in PRODUCTION state
        s_agreementInfo[agreementAddress] = AgreementInfo({
            attackModerator: agreementOwner,
            deadlineTimestamp: 0,
            promotionRequestedTimestamp: 0,
            attackRequested: false,
            attackApproved: false,
            promoted: true, // Directly promoted
            corrupted: false,
            isRegistered: true
        });

        emit AgreementStateChanged(agreementAddress, ContractState.PRODUCTION);
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Get the state of an agreement
    function _getAgreementState(address agreementAddress) internal view returns (ContractState) {
        AgreementInfo storage info = s_agreementInfo[agreementAddress];

        // Check terminal states first
        if (info.corrupted) {
            return ContractState.CORRUPTED;
        }

        if (info.promoted) {
            return ContractState.PRODUCTION;
        }

        // If not registered, it's NOT_DEPLOYED
        if (!info.isRegistered) {
            return ContractState.NOT_DEPLOYED;
        }

        // Check if promotion was requested and delay has passed
        if (info.promotionRequestedTimestamp > 0) {
            if (block.timestamp >= info.promotionRequestedTimestamp + PROMOTION_DELAY) {
                return ContractState.PRODUCTION;
            }
            return ContractState.PROMOTION_REQUESTED;
        }

        if (info.attackApproved) {
            return ContractState.UNDER_ATTACK;
        }

        // Check deadline for auto-promotion
        if (block.timestamp >= info.deadlineTimestamp) {
            return ContractState.PRODUCTION;
        }

        if (info.attackRequested) {
            return ContractState.ATTACK_REQUESTED;
        }

        // If registered but no attack requested, shouldn't happen but return NEW_DEPLOYMENT
        return ContractState.NEW_DEPLOYMENT;
    }
}
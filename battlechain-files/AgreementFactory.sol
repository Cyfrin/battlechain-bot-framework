// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Agreement } from "./Agreement.sol";
import { AgreementDetails } from "./types/AgreementTypes.sol";
import { IAgreementFactory } from "./interface/IAgreementFactory.sol";

/// @title Factory for creating Agreement contracts
/// @dev Upgradeable via UUPS pattern. Tracks all deployed agreements for validation.
// aderyn-ignore-next-line(contract-locks-ether)
contract AgreementFactory is IAgreementFactory, Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error AgreementFactory__ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event AgreementCreated(address indexed agreementAddress, address indexed owner, bytes32 indexed salt);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    string public constant VERSION = "1.0.0";

    /// @dev The Safe Harbor Registry address
    address private s_registry;

    /// @dev BattleChain CAIP-2 chain identifier (e.g., "eip155:627" for testnet, "eip155:626" for mainnet)
    string private s_battleChainCaip2ChainId;

    /// @dev Mapping to track all agreements created by this factory
    mapping(address => bool) private s_isAgreement;

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

    /// @param _initialOwner The owner of the factory
    /// @param _registry The Safe Harbor Registry address
    /// @param _battleChainCaip2ChainId The CAIP-2 chain ID for BattleChain
    function initialize(
        address _initialOwner,
        address _registry,
        string memory _battleChainCaip2ChainId
    )
        external
        initializer
    {
        if (_initialOwner == address(0)) {
            revert AgreementFactory__ZeroAddress();
        }
        if (_registry == address(0)) {
            revert AgreementFactory__ZeroAddress();
        }
        __Ownable_init(_initialOwner);
        s_registry = _registry;
        s_battleChainCaip2ChainId = _battleChainCaip2ChainId;
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAgreementFactory
    function getBattleChainCaip2ChainId() external view returns (string memory) {
        return s_battleChainCaip2ChainId;
    }

    /// @inheritdoc IAgreementFactory
    function isAgreementContract(address agreementAddress) external view returns (bool) {
        return s_isAgreement[agreementAddress];
    }

    /// @inheritdoc IAgreementFactory
    function getRegistry() external view returns (address) {
        return s_registry;
    }

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAgreementFactory
    function create(
        AgreementDetails memory details,
        address owner,
        bytes32 salt
    )
        external
        returns (address agreementAddress)
    {
        // Combine salt with msg.sender and chainid for unique addresses per sender per chain
        bytes32 finalSalt;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), chainid())
            mstore(add(ptr, 0x40), salt)
            finalSalt := keccak256(ptr, 0x60)
            mstore(0x40, add(ptr, 0x60))
        }

        Agreement agreement = new Agreement{ salt: finalSalt }(s_registry, owner, s_battleChainCaip2ChainId, details);
        agreementAddress = address(agreement);

        // Track this agreement
        s_isAgreement[agreementAddress] = true;
        emit AgreementCreated(agreementAddress, owner, salt);
    }

    function version() external pure returns (string memory) {
        return VERSION;
    }

    /*//////////////////////////////////////////////////////////////
                        UUPS UPGRADE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev Only the owner can authorize upgrades
    // aderyn-ignore-next-line(empty-block,centralization-risk)
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
}
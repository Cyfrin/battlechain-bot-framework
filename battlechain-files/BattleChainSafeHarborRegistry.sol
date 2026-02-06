// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IBattleChainSafeHarborRegistry } from "./interface/IBattleChainSafeHarborRegistry.sol";
import { IAgreementFactory } from "./interface/IAgreementFactory.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title The BattleChain Safe Harbor Registry. See www.battlechain.com for details.
// aderyn-ignore-next-line(contract-locks-ether)
contract BattleChainSafeHarborRegistry is UUPSUpgradeable, Ownable2StepUpgradeable, IBattleChainSafeHarborRegistry {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error BattleChainSafeHarborRegistry__NoAgreement();
    error BattleChainSafeHarborRegistry__ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    string constant VERSION = "1.0.0";
    mapping(address entity => address details) private s_agreements;
    mapping(string caip2ChainId => bool valid) private s_validChains;

    /// @dev The agreement factory address
    address private s_agreementFactory;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event BattleChainSafeHarborAdoption(address indexed entity, address newDetails);
    event ChainValiditySet(string caip2ChainId, bool valid);
    event AgreementFactorySet(address indexed factory);

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner,
        string[] memory initialValidChains,
        address agreementFactory
    )
        external
        initializer
    {
        if (agreementFactory == address(0)) {
            revert BattleChainSafeHarborRegistry__ZeroAddress();
        }
        __Ownable_init_unchained(owner);
        s_agreementFactory = agreementFactory;
        emit AgreementFactorySet(agreementFactory);

        uint256 length = initialValidChains.length;
        // aderyn-ignore-next-line(costly-loop)
        for (uint256 i; i < length; ++i) {
            emit ChainValiditySet(initialValidChains[i], true);
            s_validChains[initialValidChains[i]] = true;
        }
    }

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Function that sets a list of chains as valid in the registry.
    /// @param caip2ChainIds The CAIP-2 IDs of the chains to mark as valid.
    // aderyn-ignore-next-line(centralization-risk)
    function setValidChains(string[] calldata caip2ChainIds) external onlyOwner {
        // aderyn-ignore-next-line(costly-loop)
        for (uint256 i; i < caip2ChainIds.length; ++i) {
            emit ChainValiditySet(caip2ChainIds[i], true);
            s_validChains[caip2ChainIds[i]] = true;
        }
    }

    /// @notice Function that marks a list of chains as invalid in the registry.
    /// @param caip2ChainIds The CAIP-2 IDs of the chains to mark as invalid.
    // aderyn-ignore-next-line(centralization-risk)
    function setInvalidChains(string[] calldata caip2ChainIds) external onlyOwner {
        // aderyn-ignore-next-line(costly-loop)
        for (uint256 i; i < caip2ChainIds.length; ++i) {
            emit ChainValiditySet(caip2ChainIds[i], false);
            s_validChains[caip2ChainIds[i]] = false;
        }
    }

    /// @notice Set the agreement factory address.
    /// @param factory The new agreement factory address.
    // aderyn-ignore-next-line(centralization-risk)
    function setAgreementFactory(address factory) external onlyOwner {
        if (factory == address(0)) {
            revert BattleChainSafeHarborRegistry__ZeroAddress();
        }
        emit AgreementFactorySet(factory);
        s_agreementFactory = factory;
    }

    /// @notice Adds an existing agreement to the registry for the sender.
    /// @param agreementAddress The address of the agreement to adopt.
    function adoptSafeHarbor(address agreementAddress) external {
        emit BattleChainSafeHarborAdoption(msg.sender, agreementAddress);
        s_agreements[msg.sender] = agreementAddress;
    }

    /*//////////////////////////////////////////////////////////////
                   INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // aderyn-ignore-next-line(centralization-risk,empty-block)
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Get the agreement address for the adopter.
    /// @param adopter The adopter to query.
    /// @return address The agreement address.
    function getAgreement(address adopter) external view returns (address) {
        address agreement = s_agreements[adopter];

        if (agreement != address(0)) {
            return agreement;
        }

        revert BattleChainSafeHarborRegistry__NoAgreement();
    }

    /// @notice Function that returns if a chain is valid.
    /// @param _caip2ChainId The CAIP-2 ID of the chain to check.
    /// @return bool True if the chain is valid, false otherwise.
    function isChainValid(string calldata _caip2ChainId) external view returns (bool) {
        return s_validChains[_caip2ChainId];
    }

    /// @notice Check if an agreement is valid (created by the agreement factory).
    /// @param agreementAddress The agreement address to check.
    /// @return True if the agreement was created by the factory.
    function isAgreementValid(address agreementAddress) external view returns (bool) {
        if (s_agreementFactory == address(0)) {
            return false;
        }
        return IAgreementFactory(s_agreementFactory).isAgreementContract(agreementAddress);
    }

    /// @notice Get the agreement factory address.
    /// @return The agreement factory address.
    function getAgreementFactory() external view returns (address) {
        return s_agreementFactory;
    }

    /// @notice Returns the version of the BattleChain Safe Harbor Registry contract.
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
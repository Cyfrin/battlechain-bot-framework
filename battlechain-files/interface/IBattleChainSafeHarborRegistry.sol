// SPDX-License-Identifier: MIT
// aderyn-ignore-next-line(unspecific-solidity-pragma,push-zero-opcode)
pragma solidity ^0.8.24;

interface IBattleChainSafeHarborRegistry {
    /*//////////////////////////////////////////////////////////////
                    OWNER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Set the agreement factory address
    /// @param factory The new agreement factory address
    function setAgreementFactory(address factory) external;

    /*//////////////////////////////////////////////////////////////
                        USER READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Get the agreement address for the adopter. Recursively queries fallback registries.
    /// @param adopter The adopter to query.
    /// @return address The agreement address.
    function getAgreement(address adopter) external view returns (address);

    /// @notice Function that returns if a chain is valid.
    /// @param caip2ChainId The CAIP-2 ID of the chain to check.
    /// @return bool True if the chain is valid, false otherwise.
    function isChainValid(string calldata caip2ChainId) external view returns (bool);

    /// @notice Check if an agreement is valid (created by the agreement factory)
    /// @param agreementAddress The agreement address to check
    /// @return True if the agreement was created by the factory
    function isAgreementValid(address agreementAddress) external view returns (bool);

    /// @notice Get the agreement factory address
    /// @return The agreement factory address
    function getAgreementFactory() external view returns (address);
}
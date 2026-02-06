// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AgreementDetails } from "../types/AgreementTypes.sol";

interface IAgreementFactory {
    /*//////////////////////////////////////////////////////////////
                                 GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the Safe Harbor Registry address
    function getRegistry() external view returns (address);

    /// @notice Returns the BattleChain CAIP-2 chain ID
    function getBattleChainCaip2ChainId() external view returns (string memory);

    /// @notice Checks if an address is an Agreement contract created by this factory
    /// @param agreementAddress The address to check
    /// @return True if the address was created by this factory
    function isAgreementContract(address agreementAddress) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates an Agreement contract using CREATE2 for deterministic addresses
    /// @param details The agreement details
    /// @param owner The owner of the agreement
    /// @param salt A salt for deterministic deployment (combined with msg.sender and chainid)
    /// @return agreementAddress The address of the created agreement
    function create(
        AgreementDetails memory details,
        address owner,
        bytes32 salt
    )
        external
        returns (address agreementAddress);
}
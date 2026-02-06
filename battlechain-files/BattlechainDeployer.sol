// SPDX-License-Identifier: MIT
/// @dev We use 0.8.23 to be compatible with CreateX
pragma solidity 0.8.23;

import { CreateX } from "src/CreateX.sol";
import { IAttackRegistry } from "src/interface/IAttackRegistry.sol";

/// @title BattleChainDeployer
/// @notice Extends CreateX to automatically register deployments with AttackRegistry
/// @dev All deployments through this contract will be recorded for BattleChain attack mode eligibility
contract BattleChainDeployer is CreateX {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error BattleChainDeployer__ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev The AttackRegistry address
    IAttackRegistry public immutable ATTACK_REGISTRY;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @param attackRegistry The AttackRegistry address
    constructor(address attackRegistry) {
        if (attackRegistry == address(0)) {
            revert BattleChainDeployer__ZeroAddress();
        }
        ATTACK_REGISTRY = IAttackRegistry(attackRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL REGISTRATION HOOK
    //////////////////////////////////////////////////////////////*/
    /// @dev Registers the deployed contract with AttackRegistry
    function _registerDeployment(address newContract) internal {
        ATTACK_REGISTRY.registerDeployment(newContract, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                           CREATE OVERRIDES
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc CreateX
    function deployCreate(bytes memory initCode) public payable override returns (address newContract) {
        newContract = super.deployCreate(initCode);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreateAndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    )
        public
        payable
        override
        returns (address newContract)
    {
        newContract = super.deployCreateAndInit(initCode, data, values, refundAddress);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreateAndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values
    )
        public
        payable
        override
        returns (address newContract)
    {
        newContract = super.deployCreateAndInit(initCode, data, values);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreateClone(
        address implementation,
        bytes memory data
    )
        public
        payable
        override
        returns (address proxy)
    {
        proxy = super.deployCreateClone(implementation, data);
        _registerDeployment(proxy);
    }

    /*//////////////////////////////////////////////////////////////
                          CREATE2 OVERRIDES
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc CreateX
    function deployCreate2(bytes32 salt, bytes memory initCode) public payable override returns (address newContract) {
        newContract = super.deployCreate2(salt, initCode);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate2(bytes memory initCode) public payable override returns (address newContract) {
        newContract = super.deployCreate2(initCode);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate2AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    )
        public
        payable
        override
        returns (address newContract)
    {
        newContract = super.deployCreate2AndInit(salt, initCode, data, values, refundAddress);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate2AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values
    )
        public
        payable
        override
        returns (address newContract)
    {
        newContract = super.deployCreate2AndInit(salt, initCode, data, values);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate2AndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    )
        public
        payable
        override
        returns (address newContract)
    {
        newContract = super.deployCreate2AndInit(initCode, data, values, refundAddress);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate2AndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values
    )
        public
        payable
        override
        returns (address newContract)
    {
        newContract = super.deployCreate2AndInit(initCode, data, values);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate2Clone(
        bytes32 salt,
        address implementation,
        bytes memory data
    )
        public
        payable
        override
        returns (address proxy)
    {
        proxy = super.deployCreate2Clone(salt, implementation, data);
        _registerDeployment(proxy);
    }

    /// @inheritdoc CreateX
    function deployCreate2Clone(
        address implementation,
        bytes memory data
    )
        public
        payable
        override
        returns (address proxy)
    {
        proxy = super.deployCreate2Clone(implementation, data);
        _registerDeployment(proxy);
    }

    /*//////////////////////////////////////////////////////////////
                          CREATE3 OVERRIDES
    //////////////////////////////////////////////////////////////*/
    /// @inheritdoc CreateX
    function deployCreate3(bytes32 salt, bytes memory initCode) public payable override returns (address newContract) {
        newContract = super.deployCreate3(salt, initCode);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate3(bytes memory initCode) public payable override returns (address newContract) {
        newContract = super.deployCreate3(initCode);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate3AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    )
        public
        payable
        override
        returns (address newContract)
    {
        newContract = super.deployCreate3AndInit(salt, initCode, data, values, refundAddress);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate3AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values
    )
        public
        payable
        override
        returns (address newContract)
    {
        newContract = super.deployCreate3AndInit(salt, initCode, data, values);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate3AndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    )
        public
        payable
        override
        returns (address newContract)
    {
        newContract = super.deployCreate3AndInit(initCode, data, values, refundAddress);
        _registerDeployment(newContract);
    }

    /// @inheritdoc CreateX
    function deployCreate3AndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values
    )
        public
        payable
        override
        returns (address newContract)
    {
        newContract = super.deployCreate3AndInit(initCode, data, values);
        _registerDeployment(newContract);
    }
}
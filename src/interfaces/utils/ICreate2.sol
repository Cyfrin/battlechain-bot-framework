// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
interface ICreate2Deployer {
    function deploy(uint256 amount, bytes32 salt, bytes memory bytecode) external returns (address);
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address);
    function computeAddressWithDeployer(bytes32 salt, bytes32 bytecodeHash, address deployer) external pure returns (address);
}

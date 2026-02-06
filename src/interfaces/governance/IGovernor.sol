// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
interface IGovernorBravo {
      function propose(
          address[] memory targets,
          uint256[] memory values,
          string[] memory signatures,
          bytes[] memory calldatas,
          string memory description
      ) external returns (uint256);

      function queue(uint256 proposalId) external;
      function execute(uint256 proposalId) external payable;
      function cancel(uint256 proposalId) external;
      function castVote(uint256 proposalId, uint8 support) external;
      function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external;
      function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external;

      function getActions(uint256 proposalId) external view returns (
          address[] memory targets,
          uint256[] memory values,
          string[] memory signatures,
          bytes[] memory calldatas
      );
      function getReceipt(uint256 proposalId, address voter) external view returns (bool hasVoted, uint8 support, uint96 votes);
      function state(uint256 proposalId) external view returns (uint8);
      function proposals(uint256 proposalId) external view returns (
          uint256 id,
          address proposer,
          uint256 eta,
          uint256 startBlock,
          uint256 endBlock,
          uint256 forVotes,
          uint256 againstVotes,
          uint256 abstainVotes,
          bool canceled,
          bool executed
      );
      function proposalThreshold() external view returns (uint256);
      function quorumVotes() external view returns (uint256);
  }

  interface ITimelock {
      function delay() external view returns (uint256);
      function GRACE_PERIOD() external view returns (uint256);
      function acceptAdmin() external;
      function queuedTransactions(bytes32 hash) external view returns (bool);
      function queueTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external returns (bytes32);
      function cancelTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external;
      function executeTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external payable returns (bytes memory);
  }
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./BattleChainSetup.t.sol";

/// @notice Minimal WETH mock — only needs decimals() for Oracle pricing to work.
///         When weth == quoteToken, _getPriceByType short-circuits to 1:1 and
///         _getValueByType calls decimals() to normalize amounts.
contract MockWETH {
    function decimals() external pure returns (uint8) {
        return 18;
    }
}

/// @title BattleChainHelpers
/// @notice Helpers for creating agreements and walking through the attack-mode lifecycle.
///         _createAgreement is prank-free and mirrors what a protocol would do on-chain.
///         _requestAndApproveAttack is test-only scaffolding for the DAO approval flow.
abstract contract BattleChainHelpers is BattleChainSetup {
    /// @notice Deployed MockWETH address — set weth = quoteToken = this on attack contracts
    ///         so the Oracle prices ETH at 1:1 without needing Chainlink or Uniswap.
    address public mockWETH;

    function setUp() public virtual override {
        super.setUp();
        mockWETH = address(new MockWETH());
    }

    /// @notice Create a Safe Harbor agreement via the AgreementFactory.
    ///         No vm.prank or vm.warp — caller is msg.sender to the factory (permissionless).
    /// @param protocolName     Human-readable protocol name stored in the agreement
    /// @param scopeTargets     Contract addresses to include in the BattleChain scope
    /// @param recoveryAddr     Address that receives recovered funds
    /// @param bountyTerms      Full bounty terms (percentage, cap, retainable, identity, etc.)
    /// @param owner            Owner of the new Agreement (receives onlyOwner privileges)
    /// @param salt             CREATE2 salt for deterministic deployment (combined with caller + chainid)
    /// @return agr             The deployed Agreement contract
    function _createAgreement(
        string memory protocolName,
        address[] memory scopeTargets,
        address recoveryAddr,
        BountyTerms memory bountyTerms,
        address owner,
        bytes32 salt
    ) internal returns (Agreement agr) {
        // -- Build accounts from scope target addresses --
        AgreementTypes.Account[] memory accounts = new AgreementTypes.Account[](scopeTargets.length);
        for (uint256 i = 0; i < scopeTargets.length; i++) {
            accounts[i] = AgreementTypes.Account({
                accountAddress: vm.toString(scopeTargets[i]),
                childContractScope: ChildContractScope.None
            });
        }

        // -- Build chain entry for BattleChain --
        AgreementTypes.Chain[] memory chains = new AgreementTypes.Chain[](1);
        chains[0] = AgreementTypes.Chain({
            assetRecoveryAddress: vm.toString(recoveryAddr),
            accounts: accounts,
            caip2ChainId: BATTLECHAIN_CAIP2
        });

        // -- Assemble full agreement details --
        Contact[] memory contacts = new Contact[](0);
        AgreementDetails memory details = AgreementDetails({
            protocolName: protocolName,
            contactDetails: contacts,
            chains: chains,
            bountyTerms: bountyTerms,
            agreementURI: ""
        });

        // -- Deploy via factory --
        address agreementAddr = agreementFactory.create(details, owner, salt);
        agr = Agreement(agreementAddr);
    }

    /// @notice Test helper: set commitment window, request attack mode, and DAO-approve.
    ///         Uses vm.prank — this is test scaffolding, not production code.
    /// @param agr                 The agreement to put into UNDER_ATTACK state
    /// @param commitmentDuration  Commitment window length (must be >= 7 days for AttackRegistry)
    function _requestAndApproveAttack(Agreement agr, uint256 commitmentDuration) internal {
        address owner = agr.owner();

        // Protocol owner sets commitment window
        vm.prank(owner);
        agr.extendCommitmentWindow(block.timestamp + commitmentDuration);

        // Protocol owner requests attack mode (non-authorized path, for externally deployed contracts)
        vm.prank(owner);
        attackRegistry.requestUnderAttackByNonAuthorized(address(agr));

        // DAO moderator approves → state becomes UNDER_ATTACK
        vm.prank(DAO_MODERATOR);
        attackRegistry.approveAttack(address(agr));
    }
}

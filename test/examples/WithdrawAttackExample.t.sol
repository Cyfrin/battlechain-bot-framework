// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../base/BattleChainHelpers.t.sol";
import "../../src/AttackBase.sol";

// ============ Vulnerable Target ============

/// @title VulnerableWithdraw
/// @notice A buggy contract: anyone can withdraw all ETH (no access control)
contract VulnerableWithdraw {
    function deposit() external payable {}

    /// @dev BUG: No access control — anyone can drain the contract
    function withdraw() external {
        (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "withdraw failed");
    }

    receive() external payable {}
}

// ============ Whitehat Attack ============

/// @title WhitehatAttack
/// @notice Exploits VulnerableWithdraw and distributes funds per agreement terms.
///         Only overrides _attack() — uses the default attack() flow
///         (snapshot → exploit → profit calculation → distribution).
contract WhitehatAttack is AttackBase {
    /// @param _attackRegistry  Address of the BattleChain AttackRegistry
    /// @param _weth            WETH address used by Oracle for ETH pricing
    constructor(address _attackRegistry, address _weth) AttackBase(_attackRegistry) {
        weth = _weth;
        quoteToken = _weth; // weth == quoteToken → Oracle prices ETH at 1:1
    }

    function _attack(address target) internal override {
        VulnerableWithdraw(payable(target)).withdraw();
    }
}

// ============ Tests ============

/// @title WithdrawAttackExampleTest
/// @notice End-to-end tests demonstrating the full whitehat attack workflow
///         using real BattleChain contracts deployed behind UUPS proxies.
contract WithdrawAttackExampleTest is BattleChainHelpers {
    /// @dev Reusable bounty terms for the standard test case (10%, retainable)
    function _defaultBountyTerms() internal pure returns (BountyTerms memory) {
        return BountyTerms({
            bountyPercentage: 10, //10% bounty
            bountyCapUsd: 0,
            retainable: true,
            identity: IdentityRequirements.Anonymous,
            diligenceRequirements: "",
            aggregateBountyCapUsd: 0
        });
    }

    /// @notice Full whitehat workflow: deploy → fund → create agreement → approve → attack → verify
    function test_fullWhitehatWorkflow() public {

        // STEP 1. Deploy and fund the vulnerable contract
        VulnerableWithdraw vulnerable = new VulnerableWithdraw();
        vm.deal(address(this), 10 ether);
        vulnerable.deposit{value: 10 ether}();
        assertEq(address(vulnerable).balance, 10 ether, "Vulnerable should hold 10 ETH");

        // STEP 2. Protocol creates agreement with vulnerable contract in scope
        address[] memory targets = new address[](1);
        targets[0] = address(vulnerable);
        Agreement agr = _createAgreement(
            "VulnerableProtocol", targets, RECOVERY_ADDRESS, _defaultBountyTerms(), PROTOCOL_OWNER, bytes32(0)
        );

        // STEP 3. Request attack mode + DAO approves (test scaffolding)
        _requestAndApproveAttack(agr, 30 days);

        // STEP 4. Deploy and execute the whitehat attack
        vm.prank(WHITEHAT);
        WhitehatAttack whitehatAttack = new WhitehatAttack(address(attackRegistry), mockWETH);
        vm.prank(WHITEHAT);
        whitehatAttack.attack(address(vulnerable));

        // STEP 5. Verify fund distribution
        //    bountyPercentage = 10, retainable = true
        //    Bounty:   10 ETH * 10 / 100 = 1 ETH (kept by whitehat contract)
        //    Recovery: 10 ETH - 1 ETH    = 9 ETH (sent to recovery address)
        assertEq(address(vulnerable).balance, 0, "Vulnerable should be drained");
        assertEq(RECOVERY_ADDRESS.balance, 9 ether, "Recovery should receive 9 ETH");
        assertEq(address(whitehatAttack).balance, 1 ether, "Whitehat contract should retain 1 ETH bounty");
    }

    /// @notice Attacking a contract not registered as under attack should revert
    function test_revertWhen_targetNotUnderAttack() public {
        VulnerableWithdraw unregistered = new VulnerableWithdraw();
        vm.deal(address(unregistered), 1 ether);

        vm.prank(WHITEHAT);
        WhitehatAttack whitehatAttack = new WhitehatAttack(address(attackRegistry), mockWETH);

        vm.prank(WHITEHAT);
        vm.expectRevert(
            abi.encodeWithSelector(AttackBase.TargetNotUnderAttack.selector, address(unregistered))
        );
        whitehatAttack.attack(address(unregistered));
    }

    /// @notice Contract registered in AttackRegistry but removed from Agreement scope should revert.
    ///         Simulates: protocol adds two contracts → enters attack mode → commitment expires →
    ///         removes one contract from scope → whitehat tries to attack the removed contract.
    function test_revertWhen_targetNotInScope() public {
        VulnerableWithdraw inScope = new VulnerableWithdraw();
        VulnerableWithdraw outOfScope = new VulnerableWithdraw();

        // Create agreement with BOTH contracts in scope
        address[] memory targets = new address[](2);
        targets[0] = address(inScope);
        targets[1] = address(outOfScope);
        Agreement agr = _createAgreement(
            "TwoContractProtocol", targets, RECOVERY_ADDRESS, _defaultBountyTerms(), PROTOCOL_OWNER, bytes32(uint256(1))
        );

        // Request + approve with 8-day commitment (minimum is 7 days)
        _requestAndApproveAttack(agr, 8 days);

        // Warp past commitment window (8 days) but before promotion deadline (14 days)
        vm.warp(block.timestamp + 9 days);

        // Protocol owner removes outOfScope from agreement
        string[] memory toRemove = new string[](1);
        toRemove[0] = vm.toString(address(outOfScope));
        vm.prank(PROTOCOL_OWNER);
        agr.removeAccounts(BATTLECHAIN_CAIP2, toRemove);

        // outOfScope is still in AttackRegistry mapping but no longer in Agreement scope
        vm.prank(WHITEHAT);
        WhitehatAttack whitehatAttack = new WhitehatAttack(address(attackRegistry), mockWETH);

        vm.prank(WHITEHAT);
        vm.expectRevert(
            abi.encodeWithSelector(AttackBase.TargetNotInScope.selector, address(outOfScope), address(agr))
        );
        whitehatAttack.attack(address(outOfScope));
    }

    /// @notice When retainable = false, ALL funds go to recovery, whitehat contract keeps 0
    function test_nonRetainableBounty() public {
        VulnerableWithdraw target = new VulnerableWithdraw();
        vm.deal(address(this), 10 ether);
        target.deposit{value: 10 ether}();

        // Create agreement with retainable = false
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        BountyTerms memory nonRetainableTerms = BountyTerms({
            bountyPercentage: 10, //10%
            bountyCapUsd: 0,
            retainable: false,
            identity: IdentityRequirements.Anonymous,
            diligenceRequirements: "",
            aggregateBountyCapUsd: 0
        });
        Agreement agr = _createAgreement(
            "NonRetainableProtocol", targets, RECOVERY_ADDRESS, nonRetainableTerms, PROTOCOL_OWNER, bytes32(uint256(2))
        );
        _requestAndApproveAttack(agr, 30 days);

        vm.prank(WHITEHAT);
        WhitehatAttack whitehatAttack = new WhitehatAttack(address(attackRegistry), mockWETH);
        vm.prank(WHITEHAT);
        whitehatAttack.attack(address(target));

        // All funds go to recovery when retainable = false
        assertEq(address(target).balance, 0, "Target should be drained");
        assertEq(RECOVERY_ADDRESS.balance, 10 ether, "Recovery should receive ALL 10 ETH");
        assertEq(address(whitehatAttack).balance, 0, "Whitehat should retain 0 ETH");
    }
}

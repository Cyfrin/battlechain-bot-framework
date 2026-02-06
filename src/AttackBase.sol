// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/battlechain-core/IAttackRegistry.sol";
import "./interfaces/battlechain-core/IAgreement.sol";
import "./interfaces/token-standards/IERC20.sol";
import "./Oracle.sol";
import "./TokenHelper.sol";

/// @title AttackBase
/// @notice Base contract for whitehat attack implementations
/// @dev Handles target validation, snapshotting, profit calculation, and fund distribution
abstract contract AttackBase is Oracle, TokenHelper {

    // ============ State ============

    IAttackRegistry public immutable ATTACK_REGISTRY;

    address public recoveryAddress;
    uint256 public bountyPercentage; // Percentage (0-100)
    bool public retainable;

    /// @notice Tokens involved in the attack (for profit tracking)
    address[] public attackTokens;

    /// @notice Price type to use for profit calculation
    PriceType public priceType;

    // ============ Errors ============

    error TargetNotUnderAttack(address target);
    error TargetNotInScope(address target, address agreement);
    error BountyTransferFailed();
    error InvalidRecoveryAddress();
    error InvalidAddressLength();
    error RecoveryAddressNotFound(string caip2ChainId);

    // ============ Events ============

    event AttackExecuted(
        address indexed target,
        uint256 totalProfitValue,
        uint256 bountyValue
    );

    event FundsDistributed(
        address indexed target,
        address indexed token,
        uint256 totalRecovered,
        uint256 bountyAmount,
        uint256 recoveryAmount
    );

    // ============ Constructor ============

    constructor(address _attackRegistry) {
        ATTACK_REGISTRY = IAttackRegistry(_attackRegistry);
        priceType = PriceType.AUTO; // Default to auto (Chainlink -> TWAP fallback)
    }

    // ============ Main Attack Flow ============

    /// @notice Execute attack with automatic snapshotting and distribution
    /// @param target The target contract to attack
    /// @return totalProfitValue Total profit in quoteToken terms
    function attack(address target) external virtual returns (uint256 totalProfitValue) {
        // 1. Validate target
        _validTarget(target);

        // 2. Snapshot balances before attack
        _snapshotAll();

        // 3. Execute the attack (implemented by child contract)
        _attack(target);

        // 4. Calculate profit and distribute funds
        totalProfitValue = _finalizeAttack(target);
    }

    /// @notice Override this with your exploit logic
    function _attack(address target) internal virtual;

    // ============ Snapshotting ============

    /// @notice Snapshot ETH and all attack tokens
    function _snapshotAll() internal {
        _snapshotETH();
        for (uint256 i = 0; i < attackTokens.length; i++) {
            _snapshotTokens(attackTokens[i]);
        }
    }

    // ============ Profit Calculation ============

    /// @notice Calculate total profit across all tokens in quoteToken terms
    /// @return totalProfitValue Total profit value (18 decimals)
    function _calculateTotalProfit() internal view returns (uint256 totalProfitValue) {
        // ETH profit
        uint256 ethProfit = _ethProfitSince();
        if (ethProfit > 0) {
            totalProfitValue += _getValueByType(weth, ethProfit, priceType);
        }

        // Token profits
        for (uint256 i = 0; i < attackTokens.length; i++) {
            uint256 tokenProfit = _profitSince(attackTokens[i]);
            if (tokenProfit > 0) {
                totalProfitValue += _getValueByType(attackTokens[i], tokenProfit, priceType);
            }
        }
    }

    /// @notice Get profit amounts for each token (not values)
    /// @return ethProfit ETH profit amount
    /// @return tokenProfits Array of token profit amounts
    function _getProfitAmounts() internal view returns (uint256 ethProfit, uint256[] memory tokenProfits) {
        ethProfit = _ethProfitSince();
        tokenProfits = new uint256[](attackTokens.length);
        for (uint256 i = 0; i < attackTokens.length; i++) {
            tokenProfits[i] = _profitSince(attackTokens[i]);
        }
    }

    // ============ Fund Distribution ============

    /// @notice Finalize attack: calculate profits and distribute all funds
    /// @param target The target that was attacked
    /// @return totalProfitValue Total profit in quoteToken terms
    function _finalizeAttack(address target) internal returns (uint256 totalProfitValue) {
        totalProfitValue = _calculateTotalProfit();

        // Distribute ETH if any profit
        uint256 ethProfit = _ethProfitSince();
        if (ethProfit > 0) {
            _distributeFunds(target, address(0), ethProfit);
        }

        // Distribute each token if any profit
        for (uint256 i = 0; i < attackTokens.length; i++) {
            uint256 tokenProfit = _profitSince(attackTokens[i]);
            if (tokenProfit > 0) {
                _distributeFunds(target, attackTokens[i], tokenProfit);
            }
        }

        // Calculate bounty value for event
        uint256 bountyValue = (totalProfitValue * bountyPercentage) / 100;
        emit AttackExecuted(target, totalProfitValue, bountyValue);
    }

    /// @notice Distribute funds for a single token
    /// @param target The target contract
    /// @param token Token address (address(0) for ETH)
    /// @param totalRecovered Total amount recovered
    function _distributeFunds(address target, address token, uint256 totalRecovered) internal {
        // Calculate bounty
        uint256 bounty = (totalRecovered * bountyPercentage) / 100;
        uint256 toRecover = retainable ? totalRecovered - bounty : totalRecovered;

        if (token == address(0)) {
            // ETH distribution
            (bool success,) = payable(recoveryAddress).call{value: toRecover}("");
            if (!success) revert BountyTransferFailed();
        } else {
            // Token distribution
            bool success = IERC20(token).transfer(recoveryAddress, toRecover);
            if (!success) revert BountyTransferFailed();
        }

        emit FundsDistributed(target, token, totalRecovered, bounty, toRecover);
    }

    /// @notice Distribute all current balances (use if _finalizeAttack doesn't fit your flow)
    function _distributeAll(address target) internal {
        // Distribute ETH
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            _distributeFunds(target, address(0), ethBalance);
        }

        // Distribute all tokens
        for (uint256 i = 0; i < attackTokens.length; i++) {
            uint256 tokenBalance = _balanceOf(attackTokens[i]);
            if (tokenBalance > 0) {
                _distributeFunds(target, attackTokens[i], tokenBalance);
            }
        }
    }

    // ============ Target Validation ============

    /// @notice Verify target is valid for attack
    function _validTarget(address target) internal {
        // Check 1: Is contract under attack?
        if (!ATTACK_REGISTRY.isTopLevelContractUnderAttack(target)) {
            revert TargetNotUnderAttack(target);
        }

        // Check 2: Is contract in Agreement scope?
        address agreementAddr = ATTACK_REGISTRY.getAgreementForContract(target);
        IAgreement agreement = IAgreement(agreementAddr);

        if (!agreement.isContractInScope(target)) {
            revert TargetNotInScope(target, agreementAddr);
        }

        // Cache bounty info
        IAgreement.BountyTerms memory terms = agreement.getBountyTerms();
        bountyPercentage = terms.bountyPercentage;
        retainable = terms.retainable;

        // Get recovery address
        recoveryAddress = _getRecoveryAddress(agreement);
        if (recoveryAddress == address(0)) {
            revert InvalidRecoveryAddress();
        }
    }

    /// @notice Extract recovery address from Agreement
    function _getRecoveryAddress(IAgreement agreement) internal view returns (address) {
        string memory battleChainId = agreement.getBattleChainCaip2ChainId();
        IAgreement.AgreementDetails memory details = agreement.getDetails();

        for (uint256 i = 0; i < details.chains.length; i++) {
            if (_stringsEqual(details.chains[i].caip2ChainId, battleChainId)) {
                return _parseAddress(details.chains[i].assetRecoveryAddress);
            }
        }

        revert RecoveryAddressNotFound(battleChainId);
    }

    // ============ Configuration ============

    /// @notice Set tokens involved in the attack
    function _setAttackTokens(address[] memory tokens) internal {
        attackTokens = tokens;
    }

    /// @notice Add a token to attack tokens
    function _addAttackToken(address token) internal {
        attackTokens.push(token);
    }

    /// @notice Set price type for profit calculation
    function _setPriceType(PriceType _priceType) internal {
        priceType = _priceType;
    }

    // ============ Utilities ============

    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _parseAddress(string memory addrStr) internal pure returns (address addr) {
        bytes memory addrBytes = bytes(addrStr);
        uint256 length = addrBytes.length;
        uint256 start = 0;

        if (length >= 2 && addrBytes[0] == "0" && (addrBytes[1] == "x" || addrBytes[1] == "X")) {
            start = 2;
        }

        if (length - start != 40) {
            revert InvalidAddressLength();
        }

        uint160 result = 0;
        for (uint256 i = start; i < length; ++i) {
            result *= 16;
            uint8 b = uint8(addrBytes[i]);

            if (b >= 48 && b <= 57) {
                result += b - 48;
            } else if (b >= 65 && b <= 70) {
                result += b - 55;
            } else if (b >= 97 && b <= 102) {
                result += b - 87;
            } else {
                revert InvalidAddressLength();
            }
        }

        addr = address(result);
    }

    receive() external payable {}
}

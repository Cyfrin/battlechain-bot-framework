// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Real BattleChain contracts
import {Agreement} from "../../battlechain-files/Agreement.sol";
import {AgreementFactory} from "../../battlechain-files/AgreementFactory.sol";
import {AttackRegistry} from "../../battlechain-files/AttackRegistry.sol";
import {BattleChainSafeHarborRegistry} from "../../battlechain-files/BattleChainSafeHarborRegistry.sol";

// Types — import only names that don't collide with forge-std (StdChains.Chain, StdChains.Account)
import {
    AgreementDetails,
    Contact,
    BountyTerms,
    ChildContractScope,
    IdentityRequirements
} from "../../battlechain-files/types/AgreementTypes.sol";

// Chain and Account are imported via a wrapper to avoid name collision with forge-std/StdChains.sol
import "../../battlechain-files/types/AgreementTypes.sol" as AgreementTypes;

/// @title BattleChainSetup
/// @notice Deploys the full BattleChain infrastructure using real contracts behind UUPS proxies.
///         Mirrors a production deployment: SafeHarborRegistry, AgreementFactory, AttackRegistry.
abstract contract BattleChainSetup is Test {
    // ---- Actors ----
    address public PROTOCOL_OWNER;
    address public DAO_MODERATOR;
    address public WHITEHAT;
    address public RECOVERY_ADDRESS;

    // ---- Constants ----
    string public constant BATTLECHAIN_CAIP2 = "eip155:627"; // BattleChain Testnet

    // ---- Deployed infrastructure ----
    BattleChainSafeHarborRegistry public safeHarborRegistry;
    AgreementFactory public agreementFactory;
    AttackRegistry public attackRegistry;

    function setUp() public virtual {
        PROTOCOL_OWNER = makeAddr("PROTOCOL_OWNER");
        DAO_MODERATOR = makeAddr("DAO_MODERATOR");
        WHITEHAT = makeAddr("WHITEHAT");
        RECOVERY_ADDRESS = makeAddr("RECOVERY_ADDRESS");

        _deployInfrastructure();
    }

    // ================================================================
    //                     INFRASTRUCTURE DEPLOYMENT
    // ================================================================

    /// @notice Deploys all core contracts behind UUPS proxies, matching production deployment order.
    function _deployInfrastructure() internal {
        // 1. SafeHarborRegistry — deploy proxy uninitialized (circular dep with factory)
        BattleChainSafeHarborRegistry registryImpl = new BattleChainSafeHarborRegistry();
        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), "");
        safeHarborRegistry = BattleChainSafeHarborRegistry(address(registryProxy));

        // 2. AgreementFactory — needs registry address
        AgreementFactory factoryImpl = new AgreementFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(
                AgreementFactory.initialize,
                (address(this), address(safeHarborRegistry), BATTLECHAIN_CAIP2)
            )
        );
        agreementFactory = AgreementFactory(address(factoryProxy));

        // 3. Now initialize SafeHarborRegistry with the factory address
        string[] memory validChains = new string[](1);
        validChains[0] = BATTLECHAIN_CAIP2;
        safeHarborRegistry.initialize(address(this), validChains, address(agreementFactory));

        // 4. AttackRegistry — needs registry + factory
        AttackRegistry attackRegistryImpl = new AttackRegistry();
        ERC1967Proxy attackRegistryProxy = new ERC1967Proxy(
            address(attackRegistryImpl),
            abi.encodeCall(
                AttackRegistry.initialize,
                (address(this), DAO_MODERATOR, address(safeHarborRegistry), address(agreementFactory))
            )
        );
        attackRegistry = AttackRegistry(address(attackRegistryProxy));
    }

}

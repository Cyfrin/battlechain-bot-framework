# BattleChain Bot Framework

Solidity framework for building whitehat attack contracts that work with [BattleChain Safe Harbor](https://battlechain.com) agreements. Handles target validation, balance snapshotting, profit calculation, and fund distribution so whitehats can focus on writing exploit logic.

## Quick Start

```bash
git clone --recurse-submodules https://github.com/Cyfrin/battlechain-bot-framework.git
cd battlechain-bot-framework
forge build
forge test -vvv
```

## Project Structure

```
src/
  AttackBase.sol          # Core base contract — extend this for your attack
  Oracle.sol              # Price oracle (Chainlink + Uniswap V3 TWAP)
  TokenHelper.sol         # Balance snapshots, transfers, approvals, WETH utils
  FlashLoanProvider.sol   # Flash loans (Aave V2/V3, Balancer, Uniswap V2/V3, Maker)
  Swapper.sol             # DEX swaps (Uniswap V2 + V3)
  AddressBook.sol         # On-chain address registry by category
  interfaces/             # Interface definitions for DeFi protocols

battlechain-files/        # BattleChain core contracts (Agreement, AttackRegistry, etc.)

test/
  base/
    BattleChainSetup.t.sol    # Deploys full BattleChain infrastructure behind UUPS proxies
    BattleChainHelpers.t.sol  # Agreement creation + attack-mode lifecycle helpers
  examples/
    WithdrawAttackExample.t.sol  # End-to-end whitehat attack example
```

## AttackBase

`AttackBase` is the contract you extend to build a whitehat attack. It inherits from `Oracle` (pricing) and `TokenHelper` (balance tracking), and wires into BattleChain's on-chain agreement system.

### What `attack()` Does

When whitehat calls `attack(target)`, the default flow is:

```
attack(target)
  1. _validTarget(target)      — verify target is registered + in scope
  2. _snapshotAll()            — record ETH + token balances before exploit
  3. _attack(target)           — your exploit logic (abstract, you implement this)
  4. _finalizeAttack(target)   — calculate profit, distribute funds
```

#### Step 1: Target Validation (`_validTarget`)

Queries the BattleChain `AttackRegistry` to confirm:
- The target contract is currently in UNDER_ATTACK state
- The target is in the Agreement's scope (hasn't been removed)

Then caches bounty terms from the Agreement:
- `bountyPercentage` (0-100)
- `retainable` (whether whitehat keeps the bounty or it goes to recovery)
- `recoveryAddress` (parsed from the Agreement's chain details)

#### Step 2: Snapshotting (`_snapshotAll`)

Records `address(this).balance` (native ETH) and the balance of every token in the `attackTokens` array. These snapshots are the baseline for profit calculation after the exploit runs.

#### Step 3: Whitehat exploit (`_attack`)

Abstract function. This is where your exploit logic goes. After this executes, any ETH or tokens gained by the attack contract are considered profit.

#### Step 4: Finalize (`_finalizeAttack`)

- Calculates profit for ETH and each token by comparing current balances against snapshots
- Converts profits to a common quote token value using `Oracle` pricing
- Distributes funds via `_distributeFunds`:
  - If `retainable = true`: sends `(100 - bountyPercentage)%` to recovery, whitehat contract keeps the rest
  - If `retainable = false`: sends 100% to recovery
- Emits `AttackExecuted` and `FundsDistributed` events

### Minimal Example

```solidity
contract MyAttack is AttackBase {
    constructor(address _attackRegistry, address _weth) AttackBase(_attackRegistry) {
        weth = _weth;
        quoteToken = _weth; // prices ETH at 1:1, no oracle needed
    }

    function _attack(address target) internal override {
        // Your exploit logic here
        VulnerableContract(payable(target)).withdraw();
    }
}
```

Setting `weth = quoteToken` makes the Oracle short-circuit to 1:1 pricing for ETH, which is sufficient when the attack only involves native ETH. For ERC-20 tokens, configure Chainlink feeds or Uniswap V3 pools via `_setChainlinkFeed()` and `_setPreferredFee()`.

### Alternative Flow: `_distributeAll`

If `_finalizeAttack` doesn't fit your needs (e.g. Oracle dependencies are hard to satisfy, or you need custom distribution logic), you can override `attack()` and use `_distributeAll(target)` instead. This distributes the contract's entire current balance without comparing against snapshots:

```solidity
function attack(address target) external override returns (uint256) {
    _validTarget(target);
    _attack(target);
    _distributeAll(target);
    return 0;
}
```

### Configuration

| Function | Purpose |
|---|---|
| `_addAttackToken(address)` | Register a token for snapshotting and profit tracking |
| `_setAttackTokens(address[])` | Set all attack tokens at once |
| `_setPriceType(PriceType)` | Oracle strategy: `CHAINLINK`, `UNISWAP_TWAP`, `UNISWAP_SPOT`, or `AUTO` |

## Other Framework Contracts

### Oracle

Price oracle with two backends:

- **Chainlink**: Normalized to 18 decimals, with staleness checks (1 hour)
- **Uniswap V3 TWAP**: 30-minute default window, configurable per token

`AUTO` mode tries Chainlink first, falls back to TWAP.

### TokenHelper

Utilities inherited by `AttackBase`:

- **Snapshots**: `_snapshotETH()`, `_snapshotTokens(token)`, `_ethProfitSince()`, `_profitSince(token)`
- **Transfers**: `_transfer()`, `_transferETH()`, `_transferAll()`, `_transferAllETH()`
- **Approvals**: `_approve()`, `_approveMax()`, `_ensureApproval()` (handles USDT-style tokens)
- **WETH**: `_wrapETH()`, `_unwrapETH()`, `_wrapAllETH()`, `_unwrapAllWETH()`

### FlashLoanProvider

Unified flash loan interface across 6 providers:

| Provider | Callback |
|---|---|
| Aave V3 | `executeOperation()` |
| Aave V2 | `executeOperation()` |
| Balancer V2 | `receiveFlashLoan()` |
| Uniswap V3 | `uniswapV3FlashCallback()` |
| Uniswap V2 | `uniswapV2Call()` |
| Maker (ERC3156) | `onFlashLoan()` |

Override `_onFlashLoan()` with your logic. All callbacks handle repayment automatically.

### Swapper

DEX swap helpers for Uniswap V2 and V3:

- **V2**: `_swapV2ExactIn()`, `_swapV2ExactOut()`, `_swapV2Direct()` (no router, lower gas)
- **V3**: `_swapV3ExactInSingle()`, `_swapV3ExactInMulti()`, `_swapV3ExactOutSingle()`, `_swapV3Direct()`
- **Convenience**: `_swapAllV2()`, `_swapAllV3()` (swap entire balance, no slippage protection)

### AddressBook

On-chain registry for protocol addresses, organized by category (`TOKEN`, `POOL`, `ROUTER`, `LENDING`, `ORACLE`, etc.). Owner-gated registration with batch support.

## Test Infrastructure

The test suite deploys real BattleChain contracts behind UUPS proxies, matching production deployment:

1. **`BattleChainSetup`** — Deploys `SafeHarborRegistry`, `AgreementFactory`, `AttackRegistry` with correct initialization order (handles circular dependency between registry and factory)
2. **`BattleChainHelpers`** — Provides `_createAgreement()` (prank-free, mirrors real protocol usage) and `_requestAndApproveAttack()` (test scaffolding for DAO approval flow)

### Running Tests

```bash
# All tests
forge test -vvv

# Just the example
forge test -vvv --match-path test/examples/WithdrawAttackExample.t.sol
```

The example tests cover:
- Full whitehat workflow (deploy, fund, create agreement, approve, attack, verify distribution)
- Revert when target is not registered in AttackRegistry
- Revert when target was removed from Agreement scope
- Non-retainable bounty (all funds go to recovery)
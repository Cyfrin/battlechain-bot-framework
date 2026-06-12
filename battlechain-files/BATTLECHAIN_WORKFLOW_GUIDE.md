# BattleChain Workflow Guide

A comprehensive guide for protocols and whitehats to understand how BattleChain works.

---

## What is BattleChain?

BattleChain is a **pre-mainnet, post-testnet environment** with real funds. Think of it as a "battle arena" where protocols can stress-test their smart contracts before launching on mainnet, and ethical hackers (whitehats) can safely hunt for bugs with legal protection.

BattleChain is designed to be a permanent home for your protocol - not just a staging ground. Many protocols choose to maintain their BattleChain deployment indefinitely, treating it as a live L2 with continuous security testing.

### The Problem BattleChain Solves

- There's no real staging environment in Web3
- Projects go from $0 to millions overnight after an audit
- Bug bounties are difficult for ethical hackers
- We keep losing billions as an industry to hacks

### The Solution

BattleChain provides a safe environment where:
- Protocols deploy contracts with real (but limited) liquidity
- Whitehats can legally attack "Attackable" contracts
- Everyone is protected by a **Safe Harbor Agreement**

---

## Contract States Explained

Every agreement on BattleChain goes through specific states. All contracts within an agreement share the same state.

| State | What It Means | Can Whitehats Attack? |
|-------|---------------|----------------------|
| **NOT_DEPLOYED** | Contract not deployed via BattleChainDeployer (external deployment) | **NO** |
| **NEW_DEPLOYMENT** | Contract deployed via BattleChainDeployer, warming up | **NO** |
| **ATTACK_REQUESTED** | Protocol requested attack mode, waiting for DAO approval | **NO** |
| **UNDER_ATTACK** | Open season for ethical hacking | **YES** |
| **PROMOTION_REQUESTED** | Protocol wants to move to production (3-day waiting period) | **YES** |
| **PRODUCTION** | Protected like mainnet | **NO** |
| **CORRUPTED** | Contract was exploited and should no longer be used | **NO** |

### Agreement-Level State Management

In the current system, **states are tracked per agreement, not per contract**. When you request attack mode, promote, or mark as corrupted, the action applies to **all contracts** within the agreement's BattleChain scope. This simplifies management for protocols with many contracts.

### Important Timeframes

- **Promotion Window**: 14 days - If DAO takes no action on an attack request, the agreement auto-promotes to production
- **Promotion Delay**: 3 days - Waiting period after requesting promotion
- **Minimum Commitment**: 7 days - Protocols must commit to keeping terms stable for at least 7 days

---

## Part 1: Protocol Workflow

### Step 1: Create a Safe Harbor Agreement

Before deploying contracts, protocols must create a Safe Harbor Agreement that defines the terms for whitehat participation.

**What You Need to Prepare:**

1. **Protocol Name** - Your project's name

2. **Contact Details** - Emergency contacts (name + email/telegram/phone)

3. **Chains & Contracts in Scope** - List of contracts covered by the agreement
   - Contract addresses (as strings, e.g., "0x1234...")
   - Asset recovery address (where recovered funds should be sent)
   - Chain ID in CAIP-2 format ("eip155:626" for BattleChain mainnet, "eip155:627" for testnet)

4. **Bounty Terms**:
   - **Bounty Percentage**: What % of recovered funds the whitehat keeps (0-100)
   - **Bounty Cap**: Maximum bounty in USD
   - **Retainable**: Can the whitehat keep their bounty, or must they return everything?
   - **Identity Requirements**: Anonymous, Pseudonymous, or Named (KYC)
   - **Aggregate Cap** (optional): Total cap across all whitehats for one exploit

5. **Agreement URI** - Link to the full legal agreement document (preferably on IPFS)

**How to Create:**

```
1. Call AgreementFactory.create() with:
   - Your agreement details (structured as above)
   - Owner address (who can modify the agreement)
   - A unique salt for deterministic deployment

2. The factory returns your Agreement contract address
```

**Note:** You can create the Agreement before or after deploying contracts. If you create it first, you'll need to come back and add contract addresses after deployment. If you deploy first, you can include the addresses when creating the Agreement.

### Step 2: Deploy Your Contracts

Deploy your audited contracts to BattleChain **using the BattleChainDeployer**. Note that the audit findings and the published audit report is a MUST for the BattleChain DAO to approve the contracts for whitehat attacks.

Also, the contracts should be **identical** to what you plan to use (same logic, just different parameters if needed for the chain).

**Why Use BattleChainDeployer?**

The BattleChainDeployer automatically registers your contracts with the AttackRegistry when deployed. This is the **recommended path** for protocols wanting attack mode eligibility, because:
- Your contracts are automatically recorded as deployed via BattleChain
- The deployer address is automatically authorized as the agreement owner for those contracts
- You get access to the standard `requestUnderAttack()` path

If you deploy contracts externally (not via BattleChainDeployer), you can still request attack mode using `requestUnderAttackByNonAuthorized()`, but the DAO will perform extra due diligence.

**Authorization Setup:**

After deploying, the deployer address is automatically the "authorized owner" for each contract. If your Agreement is owned by a different address (e.g., a multisig), you need to transfer authorization:

```
Call AttackRegistry.authorizeAgreementOwner(contractAddress, agreementOwnerAddress)
```

This must be called by the deployer for each contract, transferring authority to the Agreement owner who will later call `requestUnderAttack()`.

**Important - Add Liquidity:**

When deploying, you should add sufficient liquidity to make the protocol attractive for whitehats to investigate. Contracts with minimal liquidity may not attract serious security researchers as the bounty payout is a percentage of effective funds at risk.

### Step 3: Add Contracts to Your Agreement

After deployment, update your Agreement to include the new contract addresses:

```
Call Agreement.addAccounts() with:
- Chain ID (e.g., "eip155:626")
- Array of account details (address + child contract scope)
```

**Child Contract Scope Options:**

The child contract scope determines whether contracts created by your deployed contracts are ALSO covered by the Safe Harbor Agreement.

| Scope | What's Covered | Example |
|-------|----------------|---------|
| `None` | Only the contract itself | A simple token contract with no factory functionality |
| `ExistingOnly` | Contract + child contracts that exist at time of agreement | A Uniswap factory + all pools that exist NOW, but not future pools |
| `All` | Contract + all current AND future child contracts | A Uniswap factory + ALL pools (existing and any new ones created later) |
| `FutureOnly` | Contract + only child contracts created AFTER the agreement | A factory where only NEW pools are in scope |

**Example - Uniswap-style Protocol:**

Imagine you deploy a `PoolFactory` contract that creates `LiquidityPool` contracts:

```
PoolFactory (0xABC...)
  └── Creates: Pool-ETH-USDC (0x111...)
  └── Creates: Pool-BTC-USDC (0x222...)
  └── Will Create: Pool-SOL-USDC (0x333...) [future]
```

- If you choose `None`: Only `PoolFactory` is attackable. Pools are NOT covered.
- If you choose `ExistingOnly`: `PoolFactory` + `Pool-ETH-USDC` + `Pool-BTC-USDC` are covered. Future `Pool-SOL-USDC` is NOT.
- If you choose `All`: Everything is covered - factory, existing pools, AND any future pools created.
- If you choose `FutureOnly`: `PoolFactory` + only `Pool-SOL-USDC` (and other future pools). Existing pools are NOT covered.

**For most protocols with factory patterns, `All` is the recommended choice** as it ensures complete coverage of your protocol's attack surface.

### Step 4: Request Attack Mode

Now you're ready to open your contracts for ethical hacking. All operations apply to the **entire agreement** (all contracts in scope).

**Option A: Standard Request (Deployed via BattleChainDeployer)**
```
Call AttackRegistry.requestUnderAttack() with:
- Your Agreement address

This automatically includes all contracts listed in your Agreement's BattleChain scope.
Requires that you (the agreement owner) are the authorized owner for all contracts.
```

**Option B: Request for Externally Deployed Contracts**
```
Call AttackRegistry.requestUnderAttackByNonAuthorized() with:
- Your Agreement address

Use this if your contracts were NOT deployed via BattleChainDeployer.
The DAO will perform extra due diligence before approving.
```

**Option C: Skip Attack Mode (Go Directly to Production)**
```
Call AttackRegistry.goToProduction() with:
- Your Agreement address

Use this if you don't want the attack phase (e.g., already battle-tested on another chain).
Requires contracts to be deployed via BattleChainDeployer.
```

**Requirements:**
- You must be the Agreement owner
- The Agreement must have a commitment window of at least 7 days remaining
- For Option A: All contracts in scope must have you as the authorized owner

**What Happens (Options A & B):**
- Agreement state changes to `ATTACK_REQUESTED`
- A 14-day deadline starts
- Now you wait for DAO approval

### Step 5: Wait for DAO Approval

The BattleChain DAO (Registry Moderator) reviews your request to ensure:
- Your contracts don't mirror existing mainnet contracts with high TVL
- Your Agreement terms are fair
- All critical contracts are included in the agreement scope
- Contracts have gone through one or multiple private audits. DAO studies the findings of the audit before making a decision

**Once Approved:**
- Agreement state changes to `UNDER_ATTACK`
- Whitehats can now legally attack all contracts in the agreement scope

**If Rejected:**
- The DAO calls `AttackRegistry.rejectAttackRequest(agreementAddress)`
- Contract-to-agreement mappings are cleared
- You can create a new agreement and try again after addressing the DAO's concerns

**Important:** If the DAO does not approve or reject within the 14-day promotion window, the agreement auto-promotes to `PRODUCTION` and the attack opportunity is lost.

### Step 6: Monitor

While under attack:
- Monitor your contracts for any exploits
- Consider using BattleChain hacks as triggers for mainnet monitoring

**Note on Attack Duration:**

Once the DAO approves your agreement for attack mode (`UNDER_ATTACK`), it stays in this state **indefinitely** until you explicitly promote or until a successful exploit marks it as corrupted. There is no auto-promotion timer from `UNDER_ATTACK` - you have full control over when to promote.

**Perpetual Attack Mode:**

Many protocols choose to **never promote to production** and instead keep their contracts under attack. This provides:
- Continuous security testing from whitehats
- Ongoing incentive for security researchers to monitor your protocol
- A living bug bounty program with real funds at stake

### Step 7: Promote to Production

When you're confident your contracts are secure and want to end the attack period:

```
Call AttackRegistry.promote() with:
- Your Agreement address
```

**What Happens:**
- Agreement state changes to `PROMOTION_REQUESTED`
- A 3-day waiting period begins (gives whitehats a final chance to find bugs)
- After 3 days, automatically moves to `PRODUCTION`

**Cancelling a Promotion:**

If you change your mind during the 3-day waiting period:

```
Call AttackRegistry.cancelPromotion() with:
- Your Agreement address

This returns all contracts to UNDER_ATTACK state.
```

**Note that once contracts reach `PRODUCTION` (after the 3-day delay), they cannot be put back into attack mode again.**

### Step 8: Deploy to Other Chains (Optional)

Once your contracts are battle-tested on BattleChain, you may choose to deploy to other chains. If the contracts are deployed on other chains, make sure that the contract code is EXACT as the one that went into `PRODUCTION`.

**Note:** BattleChain is designed to be a permanent home for your protocol, not just a testing ground. Protocols can maintain their BattleChain deployment as their primary L2 presence while also deploying to other chains.

---

## Deploying New Contracts

When you need to add new contracts to your protocol:

1. **Deploy the Contract** - Deploy to BattleChain via BattleChainDeployer

2. **Authorize the Agreement Owner**:
   ```
   Call AttackRegistry.authorizeAgreementOwner(contractAddress, agreementOwnerAddress)
   ```

3. **Add to Agreement Scope**:
   ```
   Call Agreement.addAccounts() with the new contract address
   ```

4. **Create a New Agreement & Request Attack Mode** - Since the existing agreement may already be in a terminal state (`PRODUCTION` or `CORRUPTED`), you'll need a new agreement for new contracts:
   ```
   Call AgreementFactory.create() with the new contract details
   Call AttackRegistry.requestUnderAttack(newAgreementAddress)
   ```

5. **Wait for DAO Approval** - Once approved, whitehats can attack

---

## Upgrading Contract Implementations (Proxies)

If your protocol uses upgradeable proxies (UUPS, Transparent, etc.):

**The Good News:** As long as the **proxy address** is in your Agreement's scope, the contract remains attackable after upgrades. You don't need to re-register or re-request attack mode.

**How It Works:**
- The proxy address stays the same
- You upgrade the implementation behind it
- Since the proxy address is already in scope and `UNDER_ATTACK`, whitehats can continue attacking

**Important Warning - Silent Upgrades:**

While technically possible, **silent upgrades during active attack periods are strongly discouraged** unless you've discovered a critical bug that needs immediate patching.

Why?
- Whitehats may be mid-investigation on the old implementation
- Sudden changes invalidate ongoing security research
- It erodes trust with the security community

**Best Practice:**
- If you find a critical bug yourself, upgrade immediately (security first)
- For non-critical upgrades, consider promoting to production first, then deploying a new contract with the upgraded logic, if necessary
- Communicate upgrades to the whitehat community when possible

---

## Responding to a Successful Attack

If a whitehat successfully exploits your contract:

### Step 1: Mark the Agreement as Corrupted

Signal that the contracts in this agreement should no longer be used:

```
Call AttackRegistry.markCorrupted(agreementAddress)
```

The `CORRUPTED` state indicates:
- One or more contracts were exploited
- The contracts should no longer be trusted
- Users should migrate away from them

### Step 2: Deploy Fresh Contracts

You'll need to deploy new versions of the exploited contract(s) with the vulnerability fixed.

**Important - Contract Dependencies:**

If the exploited contract is referenced by other contracts in your protocol, you may need to redeploy those dependent contracts as well.

**Example:**
```
Your protocol has:
- Router (references Vault)
- Vault (EXPLOITED)
- Token

After exploit:
1. Deploy new Vault (VaultV2)
2. Router still points to old Vault -> Deploy new Router (RouterV2) pointing to VaultV2
3. Token has no dependencies -> Can keep existing Token
```

### Step 3: Create New Agreement and Request Attack

1. Create a new Agreement with the new contract addresses
2. Authorize the agreement owner for each new contract
3. Call `requestUnderAttack()` with the new agreement address
4. Wait for DAO approval

### Step 4: Communicate with Users

- Announce the migration path
- Help users move funds from old contracts to new ones
- Consider compensation for affected users

---

## Removing Contracts from Scope

You may want to remove contracts from your Safe Harbor Agreement scope.

### Understanding the Commitment Window (`cantChangeUntil`)

The `cantChangeUntil` timestamp is a protection mechanism for whitehats. When you request attack mode, you commit to keeping your Agreement terms stable for at least 7 days.

**Why It Exists:**

Imagine you're a whitehat who spends days investigating a protocol. You find a bug, prepare your exploit, and just before you execute - the protocol removes that contract from scope. Suddenly you have no Safe Harbor protection, and your work is wasted (or worse, you could face legal issues).

The commitment window prevents this by guaranteeing:
- Contracts cannot be removed from scope during this period
- Bounty terms cannot be made less favorable
- Whitehats can invest time with confidence

**When You CAN Remove Contracts:**
- After the `cantChangeUntil` timestamp has passed
- When the commitment window has expired

**When You CANNOT Remove Contracts:**
- During an active commitment window
- While `block.timestamp < cantChangeUntil`

**How to Remove:**

```
Call Agreement.removeAccounts() with:
- Chain ID
- Array of account addresses to remove
```

**Important:**
- You must keep at least one account per chain
- Case-sensitive matching - use exact addresses as stored
- Removing contracts while they're under attack is unfair to whitehats who may be mid-investigation

**Extending the Commitment Window:**

If you want to signal long-term commitment to whitehats:

```
Call Agreement.extendCommitmentWindow(newTimestamp)
```

This can only extend the window, never shorten it.

---

## Revising Bounty Terms

You can update your bounty terms, but there are restrictions to protect whitehats.

### When You CAN Change Terms

**Outside the Commitment Window** (after `cantChangeUntil`):
- You can make ANY changes to bounty terms
- Increase or decrease percentages
- Change caps
- Modify identity requirements

**During the Commitment Window:**
You can ONLY make changes that are MORE favorable to whitehats:
- **Increase** bounty percentage (e.g., 10% -> 15%)
- **Increase** bounty cap (e.g., $50K -> $100K)
- **Increase** aggregate cap
- **Relax** identity requirements (e.g., Named -> Anonymous)
- **Enable** retainable if it was disabled

You CANNOT:
- Decrease bounty percentage
- Decrease any caps
- Add stricter identity requirements
- Disable retainable if it was enabled

### How to Update Terms

```
Call Agreement.setBountyTerms() with:
- bountyPercentage (0-100)
- bountyCapUsd
- retainable (true/false)
- identity (Anonymous/Pseudonymous/Named)
- diligenceRequirements (string, for Named whitehats)
- aggregateBountyCapUsd (0 = no aggregate cap)
```

### Best Practice

**Do not change bounty terms while contracts are under active attack** unless you're making them more favorable.

Even outside the commitment window, suddenly reducing bounty terms while whitehats are actively investigating:
- Damages trust with the security community
- May cause whitehats to abandon your protocol
- Could result in bugs being sold to black hats instead

If you need to reduce terms, consider:
1. Announcing the change in advance
2. Giving whitehats time to submit findings under current terms
3. Promoting to production first, then adjusting terms for future attack cycles

---

## Emergency: Instant Promotion by DAO

The DAO can **instantly promote** an agreement to production in these situations:

1. **Copycat Detection** - A mainnet contract mirrors an attackable BattleChain contract
2. **High TVL Risk** - Too much money flows into an attackable contract
3. **Security Concerns** - Any situation that could endanger users

The DAO calls:
```
AttackRegistry.instantPromote(agreementAddress)
```

This immediately moves all contracts in the agreement to `PRODUCTION`, ending the attack period.

---

## Part 2: Whitehat Workflow

### When Can You Start Hunting?

**Check the Agreement State:**
- First, get the agreement for a contract: `AttackRegistry.getAgreementForContract(contractAddress)`
- Then check the state: `AttackRegistry.getAgreementState(agreementAddress)`
- Or use `AttackRegistry.isTopLevelContractUnderAttack(contractAddress)` for a simple yes/no

**You CAN Attack When:**
- State is `UNDER_ATTACK`
- State is `PROMOTION_REQUESTED` (3-day grace period)

**You CANNOT Attack When:**
- State is `NOT_DEPLOYED` (not deployed via BattleChainDeployer)
- State is `NEW_DEPLOYMENT` (warming up)
- State is `ATTACK_REQUESTED` (waiting for DAO approval)
- State is `PRODUCTION` (protected)
- State is `CORRUPTED` (already exploited)

### Pre-Attack Checklist

Before attacking, verify these critical items:

#### 1. Confirm the Contract is Attackable
```solidity
bool canAttack = AttackRegistry.isTopLevelContractUnderAttack(contractAddress);
require(canAttack, "Contract not attackable");
```

#### 2. Find the Agreement
```solidity
address agreementAddress = AttackRegistry.getAgreementForContract(contractAddress);
```

#### 3. Review Bounty Terms
```solidity
IAgreement agreement = IAgreement(agreementAddress);
BountyTerms memory terms = agreement.getBountyTerms();

// Check:
// - terms.bountyPercentage (what % you keep)
// - terms.bountyCapUsd (maximum payout)
// - terms.retainable (can you keep funds or must return all?)
// - terms.identity (do you need KYC?)
// - terms.aggregateBountyCapUsd (total cap across all hackers)
```

#### 4. Verify Contract is in Scope
```solidity
bool inScope = agreement.isContractInScope(contractAddress);
require(inScope, "Contract not in agreement scope");
```

#### 5. Check Time Remaining
```solidity
AgreementInfo memory info = AttackRegistry.getAgreementInfo(agreementAddress);

// If PROMOTION_REQUESTED, check how much time left:
// Production happens at: info.promotionRequestedTimestamp + 3 days
```

#### 6. Find Asset Recovery Address
```solidity
string memory recoveryAddress = agreement.getAssetRecoveryAddress("eip155:626");
// This is where you send recovered funds (minus your bounty if retainable)
```

### Submitting a Bug When Contract is Under Attack

When you find and exploit a vulnerability:

#### Step 1: Execute the Exploit
- Perform the attack to secure the vulnerable funds

#### Step 2: Calculate Your Bounty
```
If bounty is RETAINABLE:
  Your Bounty = MIN(recoveredAmount * bountyPercentage/100, bountyCapUsd)
  Send Remainder = recoveredAmount - Your Bounty -> Asset Recovery Address

If bounty is NOT RETAINABLE:
  Send Everything -> Asset Recovery Address
  (Protocol will pay you separately)
```

#### Step 3: Send Funds to Recovery Address
- Send the protocol's portion (or all funds if not retainable) to the asset recovery address specified in the Agreement

#### Step 4: Contact the Protocol
- Get contact details from `agreement.getDetails().contactDetails`
- Report what you found, how you exploited it, and transaction hashes

#### Step 5: Document Everything
- Keep records of all transactions
- Screenshot the contract state at time of attack
- Save Agreement terms as proof of Safe Harbor coverage

### Submitting a Bug When Contract is in Production

If a contract is in `PRODUCTION` state, **DO NOT ATTACK IT**.

Instead:

#### Option 1: Use Traditional Bug Bounty
- Find the protocol's bug bounty program (Immunefi, HackerOne, etc.)
- Submit through proper channels
- Follow responsible disclosure

#### Option 2: Contact Protocol Directly
- Use the contact details in the Agreement
- Report the vulnerability privately
- Work with them on a fix

#### Option 3: Check for Mainnet Implications
**Critical:** If the BattleChain production contract mirrors a mainnet contract, the bug may exist on mainnet too.

- **DO NOT** exploit on mainnet
- **DO NOT** publicly disclose
- Contact the protocol immediately
- Consider reporting through SEAL (Security Alliance) if the protocol is unresponsive

### Important Protections for Whitehats

#### Safe Harbor Coverage
When attacking `UNDER_ATTACK` or `PROMOTION_REQUESTED` contracts:
- You're legally protected under the Safe Harbor Agreement
- The agreement is on-chain and immutable during the commitment window
- Protocols cannot retroactively change unfavorable terms

#### Commitment Window Protection
During the commitment window (`cantChangeUntil`), protocols CANNOT:
- Reduce bounty percentage
- Reduce bounty cap
- Remove contracts from scope
- Add stricter identity requirements
- Change retainable from true to false

They CAN only make things MORE favorable for you.

#### What If Instant Promotion Happens?
If the DAO instant-promotes an agreement while you're mid-attack:
- If you already exploited: Your Safe Harbor coverage is based on state at time of exploit
- If you haven't exploited yet: Stop immediately - the contracts are now protected

---

## Quick Reference: Key Functions

### For Protocols

| Action | Function |
|--------|----------|
| Create Agreement | `AgreementFactory.create()` |
| Add Contracts to Agreement | `Agreement.addAccounts()` |
| Remove Contracts from Agreement | `Agreement.removeAccounts()` |
| Authorize Agreement Owner | `AttackRegistry.authorizeAgreementOwner()` |
| Request Attack Mode (authorized) | `AttackRegistry.requestUnderAttack()` |
| Request Attack Mode (external) | `AttackRegistry.requestUnderAttackByNonAuthorized()` |
| Skip to Production | `AttackRegistry.goToProduction()` |
| Promote to Production | `AttackRegistry.promote()` |
| Cancel Promotion | `AttackRegistry.cancelPromotion()` |
| Mark as Corrupted After Exploit | `AttackRegistry.markCorrupted()` |
| Update Bounty Terms | `Agreement.setBountyTerms()` |
| Extend Commitment Window | `Agreement.extendCommitmentWindow()` |
| Transfer Moderator Role | `AttackRegistry.transferAttackModerator()` |

### For Whitehats

| Action | Function |
|--------|----------|
| Check if Attackable | `AttackRegistry.isTopLevelContractUnderAttack()` |
| Get Agreement State | `AttackRegistry.getAgreementState()` |
| Get Agreement for Contract | `AttackRegistry.getAgreementForContract()` |
| Get Agreement Info | `AttackRegistry.getAgreementInfo()` |
| Check Contract in Scope | `Agreement.isContractInScope()` |
| Get Bounty Terms | `Agreement.getBountyTerms()` |
| Get Recovery Address | `Agreement.getAssetRecoveryAddress()` |
| Get Contact Details | `Agreement.getDetails()` |

### For DAO (Registry Moderator)

| Action | Function |
|--------|----------|
| Approve Attack Request | `AttackRegistry.approveAttack()` |
| Reject Attack Request | `AttackRegistry.rejectAttackRequest()` |
| Instant Promote to Production | `AttackRegistry.instantPromote()` |

---

## Summary: The Complete Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PROTOCOL FLOW                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. Create Agreement ──► 2. Deploy Contracts (via BattleChainDeployer)
│         │                   (+ Authorize Agreement Owner)           │
│         │                   (+ Add Liquidity)                       │
│         │                                                           │
│         └─── (Can also deploy first, then create Agreement) ────┘   │
│                              ▼                                      │
│                                                                     │
│  3. Add Contracts to Agreement ──► 4. Request Attack Mode           │
│                                       │                             │
│                                       ├── requestUnderAttack()      │
│                                       ├── requestUnderAttackByNonAuthorized()
│                                       └── goToProduction() (skip)   │
│                              ▼                                      │
│                                                                     │
│  5. Wait for DAO ──► Approved ──► UNDER ATTACK                     │
│         │                            │                              │
│         └── Rejected ──► Fix & Retry │                              │
│                                      │                              │
│  6. UNDER ATTACK (indefinite) ──────────────────────────────────── │
│     │                                                               │
│     └── Promote ──► 7. 3-Day Wait ──► 8. PRODUCTION                │
│              │                                                      │
│              └── cancelPromotion() ──► Back to UNDER_ATTACK         │
│                                                                     │
│  If Exploited: ──► markCorrupted() ──► CORRUPTED                   │
│                    ──► Deploy Fresh ──► New Agreement ──► Restart   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                         WHITEHAT FLOW                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. Check State (isTopLevelContractUnderAttack?) ──► YES ──► Continue
│                                                      NO  ──► STOP  │
│                              ▼                                      │
│                                                                     │
│  2. Get Agreement & Review Terms                                    │
│                                                                     │
│                              ▼                                      │
│                                                                     │
│  3. Verify Contract in Scope                                        │
│                                                                     │
│                              ▼                                      │
│                                                                     │
│  4. Execute Exploit                                                 │
│                                                                     │
│                              ▼                                      │
│                                                                     │
│  5. Calculate & Keep Bounty (if retainable)                         │
│                                                                     │
│                              ▼                                      │
│                                                                     │
│  6. Send Remainder to Recovery Address                              │
│                                                                     │
│                              ▼                                      │
│                                                                     │
│  7. Contact Protocol & Document                                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

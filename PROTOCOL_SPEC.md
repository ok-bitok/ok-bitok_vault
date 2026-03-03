# OK-BITOK Vault Protocol Specification

Version: 1.0  
Network: Arbitrum  
Strategy Focus: Delta-Neutral Funding and Basis Strategies  

---

## 1. Overview

OK-BITOK Vault is an on-chain capital accounting protocol designed to support structured delta-neutral strategies.

The smart contract maintains share-based NAV accounting, investor state, and fee logic, while capital deployment and trading operations are executed off-chain through a dedicated execution infrastructure.

The protocol separates:

- On-chain accounting and investor registry
- Off-chain capital deployment and market execution

This architecture enables transparent accounting while preserving operational flexibility and execution integrity.

---

## 2. On-Chain Responsibilities

The smart contract maintains:

- Investor share balances
- Net Asset Value (NAV)
- Investor base share price (profit reference point)
- Referral relationships
- VIP status
- Investor registry (historical and active)

The contract does not retain long-term idle liquidity. Deposited capital is transferred to the manager for deployment.

---

## 3. Roles

### Manager

- Deploys the contract
- Confirms deposits
- Manages liquidity provisioning for withdrawals
- Executes capital deployment and return
- Controls parameter updates
- Can initiate shutdown

### NAV Updater

- Authorized hot key
- Updates NAV via `updateNav`
- Has no access to capital or investor funds

---

## 4. Deposit Flow

Deposits follow a two-step process:

1. `deposit(amount)`
   - USDC is transferred from investor
   - A pending deposit record is created
   - No shares are minted at this stage

2. `confirmDeposit(investor, pendingId)`
   - Shares are minted based on current NAV
   - Performance fees are crystallized if applicable
   - Investor state is updated
   - Pending record is cleared

Pending deposits do not increase TVL until confirmation.

---

## 5. Share Accounting Model

Each investor holds shares representing proportional ownership of vault equity.

Investor profit is calculated as:

(current share price – investor base share price) × share balance

Each investor’s profit reference point is tracked independently.

---

## 6. Performance Fee Mechanism

Performance fees are charged only on realized profit and are paid in shares (not USDC).

Fee crystallization occurs:

- On deposit confirmation (if shares already exist)
- On withdrawal request
- On withdrawal fulfillment
- During batch crystallization
- During migration or shutdown

Fees are redistributed by transferring shares from the investor to:

- Manager (fund allocation)
- Referrer (if active)

Total shares remain constant during redistribution.

---

## 7. Withdrawal Flow

Withdrawals are initiated in USDC terms.

1. `requestWithdraw(amountUsdc)`
   - Fees are crystallized
   - Equivalent shares are reserved
   - Request is recorded

2. `fulfillWithdrawal(user)`
   - Fees are re-crystallized using current NAV
   - Shares are burned
   - USDC is transferred to the investor

Final conversion is always based on the current NAV.

Reserved shares do not participate in further operations.

---

## 8. Referral Program

- Referral binding is permanent after first deposit
- Referrer must be an existing investor
- Referrer must maintain minimum TVL to remain active
- Referral rewards are paid directly in shares
- No separate claim mechanism exists

---

## 9. VIP Status

VIP status activates when investor share value exceeds a configurable threshold.

VIP investors benefit from reduced performance fee rates.

Status is dynamically recalculated after each relevant operation.

---

## 10. Batch Fee Crystallization

The contract maintains an investor registry.

Batch crystallization allows off-chain systems to process fee updates in segments to maintain gas efficiency.

Inactive addresses remain in the registry for index stability.

---

## 11. Capital Deployment Model

The smart contract serves as an accounting layer.

Trading capital is deployed off-chain under controlled operational procedures.

Manager responsibilities include:

- Deploying capital to execution venues
- Maintaining sufficient liquidity for withdrawals
- Returning capital for settlement events

TVL is calculated as:

totalShares × NAV

Contract USDC balance is not used directly in NAV computation.

---

## 12. Shutdown Procedure

In case of protocol shutdown:

- NAV is frozen
- Fee accrual stops
- Deposits and new requests are disabled
- Investors may redeem all shares at frozen NAV

All settlements are executed through share-based accounting.

---

## 13. Security Model

- All state-changing functions are protected against reentrancy
- USDC transfers use safe transfer patterns
- Share conversions revert on invalid rounding
- Fee shares cannot exceed investor balance

---

## 14. Operational Assumptions

The protocol relies on coordinated operational capital management by the manager to ensure liquidity for withdrawals and migrations.

The smart contract enforces accounting correctness and share integrity, while execution infrastructure manages market exposure and liquidity provisioning.

---

## 15. Trust Model

OK-BITOK Vault is a managed delta-neutral strategy vault.

The smart contract guarantees:

- Transparent accounting
- Deterministic share logic
- Non-custodial investor share tracking

Capital deployment and liquidity management are conducted under defined operational procedures.

---

End of Document

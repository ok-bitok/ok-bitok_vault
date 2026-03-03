<p align="center">
  <img src="assets/ok_bitok_header_2560w.png" alt="OK-BITOK Banner" />
</p>

---

<table>
<tr>
<td width="160">
<img src="assets/Introduction.png" width="140" />
</td>
<td>

# OK-BITOK Vault

**On-Chain Structured Delta-Neutral Infrastructure**

A managed on-chain capital accounting protocol designed for disciplined delta-neutral deployment.

OK-BITOK Vault is a structured DeFi protocol designed to capture funding and basis inefficiencies while maintaining controlled directional exposure.

The protocol combines deterministic on-chain share accounting with a dedicated execution infrastructure, enabling transparent capital allocation and disciplined liquidity management.

</td>
</tr>
</table>

---

<p align="left">
  <img alt="Network" src="https://img.shields.io/badge/Network-Arbitrum-1f6feb" />
  <img alt="Asset" src="https://img.shields.io/badge/Asset-USDC-1f6feb" />
  <img alt="Language" src="https://img.shields.io/badge/Language-Solidity-1f6feb" />
  <img alt="Type" src="https://img.shields.io/badge/Vault-Managed-1f6feb" />
</p>

---

## Quick Links

- Website: https://ok-bitok.com
- Docs: https://docs.ok-bitok.com
- Smart Contract (Arbitrum): https://arbiscan.io/address/0xD772A28caf98cCF3c774c704cA9514A4914b50A0
- Protocol Specification: [Vault Protocol Specification](./PROTOCOL_SPEC.md)

---

## Protocol Summary

| Component | Responsibility |
|------------|----------------|
| Smart Contract | Share ledger, NAV storage, fee logic, referral accounting |
| Execution Stack | Market deployment, rebalancing, liquidity provisioning |
| NAV Updater | Controlled equity synchronization |
| Manager | Capital operations and settlement coordination |

TVL is derived from share supply × NAV.  
The smart contract functions as a capital accounting layer, not a trading engine.

---

## Architecture

<p align="center">
  <img src="assets/ok-bitok-vault-architecture-diagram.png" width="550" />
</p>

The system is intentionally divided into:

- On-chain deterministic accounting
- Off-chain execution infrastructure
- Controlled NAV propagation
- Structured fee crystallization

This separation preserves accounting integrity while enabling institutional-grade execution flexibility.

---

## Design Philosophy

- Capital discipline over speculation
- Deterministic accounting over opaque performance
- Operational separation over monolithic contracts
- Liquidity-aware execution and settlement

---

## Why Managed Architecture

OK-BITOK Vault is designed as a managed structure to keep the on-chain layer strictly focused on accounting integrity while allowing the execution stack to operate with:

- Market connectivity and venue-specific execution logic
- Operational risk controls and rebalancing workflows
- Liquidity provisioning for withdrawals and migrations
- Separation of duties (manager vs NAV updater)

The objective is to keep accounting deterministic on-chain and execution adaptable off-chain.

---

## Strategy Class

The vault operates within the following strategic framework:

- Delta-neutral positioning
- Funding rate capture
- Basis convergence strategies
- Controlled leverage exposure
- Liquidity-aware position sizing

The system is designed to perform in both expansionary and contractionary market regimes.

---

## Capital Lifecycle

1. Investor deposits USDC.
2. Shares are minted at current NAV.
3. Capital is deployed through execution infrastructure.
4. NAV reflects realized equity.
5. Withdrawals are settled via share redemption.

All investor ownership is represented through shares.  
Profit crystallization occurs through deterministic share redistribution.

---

## Fee Model

- Performance-based
- Crystallized in shares
- Deterministic and non-inflationary
- VIP tier adjustments supported
- Referral rewards integrated into accounting layer

No hidden dilution mechanics.

---

## Risk Model

The protocol is designed to constrain smart contract risk to accounting logic while managing strategy and liquidity operations through defined procedures.

- Market risk is minimized through delta-neutral exposure design
- Smart contract risk is limited to the accounting layer (shares, NAV, fee logic)
- Liquidity risk is managed operationally as part of capital deployment and settlement
- Role separation reduces operational blast radius (manager vs NAV updater)

---

## Security & Accounting Model

- Reentrancy protection
- Deterministic rounding safeguards
- Share supply invariants
- Registry-based batch processing
- Controlled role separation

The smart contract guarantees accounting correctness.  
Operational liquidity management is handled under defined procedures.

---

## Transparency

- Contract deployed on Arbitrum
- Public NAV accounting
- On-chain share ledger
- Explicit trust model

Smart Contract:  
https://arbiscan.io/address/0xD772A28caf98cCF3c774c704cA9514A4914b50A0

---

## Documentation

- Protocol Specification: [Vault Protocol Specification](./PROTOCOL_SPEC.md)
- Docs Portal: https://docs.ok-bitok.com
- Website: https://ok-bitok.com

---

## Contact

contact@ok-bitok.com

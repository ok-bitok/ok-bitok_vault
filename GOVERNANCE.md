# Governance Framework

## Overview

OK-BITOK Vault operates under a structured governance model designed to ensure operational control, accounting integrity, and capital protection.

The protocol separates accounting logic (on-chain) from execution infrastructure (off-chain), with clearly defined operational roles.

---

## Current Governance Model

At the current stage, governance is managed by the protocol operator.

Responsibilities include:

- Strategy deployment and capital allocation
- Risk parameter configuration
- NAV update authorization
- Liquidity management
- Infrastructure maintenance

The smart contract enforces deterministic accounting rules independently of operational discretion.

---

## Role Structure

The system operates with defined operational roles:

### Vault Contract
- Share ledger management
- NAV storage
- Performance fee crystallization
- Referral accounting
- Access control

### Execution Infrastructure
- Market execution
- Rebalancing
- Basis and funding capture
- Liquidity provisioning

### NAV Update Process
- Equity snapshot validation
- Controlled NAV propagation
- On-chain synchronization

Role separation ensures accounting integrity while enabling disciplined execution management.

---

## Upgrade Policy

Any material changes to the smart contract logic would require:

- Deployment of a new contract version
- Transparent public announcement
- Updated documentation
- Migration procedure disclosure (if applicable)

The protocol does not implement hidden upgrade mechanisms.

---

## Transparency Commitment

- Smart contract deployed on Arbitrum
- Public on-chain share accounting
- Public NAV visibility
- Versioned releases via GitHub

Governance documentation will evolve as the protocol scales.

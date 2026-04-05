# Open-Pact Roadmap

This document outlines the development path for the Open-Pact Framework and License. Our philosophy is **Trust First**: we verify the legal standard, we test the code where the developers are, and we engage the community before asking for real money.

## Phase 1: The Standard & Soft Launch (Current)
**Status: 🟢 Complete / Active**
*   **Goal:** Establish the OPL-1.1 license as the "Third Way" between MIT and Proprietary.
*   [x] **v1.1 Release:** Public launch of OPL-1.1 with Sunset, Whistleblower, and AI clauses.
*   [x] **Repository Structure:** Separate legal text (`license`) from code (`framework`).
*   [ ] **Community Review:** Gather feedback from developers and legal experts regarding Section 4 (AI Training) and Section 16 (Sunset).
*   [ ] **Reference Implementation:** Showcase the Gold DAO as a working example of a "Guild."

## Phase 2: Multi-Chain Testnet Deployment (Q3 2026)
**Status: 🔵 Planned**
*   **Strategy:** Deploy to **EVM-compatible chains with high developer activity**, ensuring the framework works where users actually build.
*   **Base Sepolia:** Prioritized for its USDC integration (the ideal royalty currency).
*   **Arbitrum Sepolia:** Prioritized for the sophisticated DAO/DeFi builder community.
*   **Polygon Amoy:** Prioritized for high-throughput micro-royalty testing.
*   **Flare Coston2:** Included as a secondary test for Oracle/Data integration capabilities.
*   **Guild Registry Dashboard:** Build a web interface allowing users to check if a company holds a valid OPL license across *any* supported chain.
*   **AI Audit Agent V1:** Release the Python-based `OPLAuditAgent` to scan GitHub for "Canary Strings" and cross-reference with the Multi-Chain Registry.

## Phase 3: Enforcement & Audits (Q4 2026)
**Status: ⚪ Upcoming**
*   **Goal:** Professional security review and robust enforcement.
*   **Smart Contract Audits:** Commission audits for the `RoyaltyRegistry` and `Whistleblower` contracts on Base and Arbitrum.
*   **Whistleblower Fund Mechanics:** Test the "Bounty Payout" flow. Simulate a violation and reward a "reporter" to prove the incentive works.
*   **CI/CD Integration:** Release a GitHub Action (`open-pact-check`) that allows companies to automatically scan their dependencies for OPL compliance.
*   **Token Economics (Draft):** Finalize the whitepaper for the **$OPL Token** — strictly for use as a utility currency for AI Agents to pay for data/bounties, not for VC speculation.

## Phase 4: Mainnet & Ecosystem (Q1 2027)
**Status: ⚪ Future**
*   **Goal:** Full public launch and commercial adoption.
*   **Mainnet Deployment:** Deploy final audited contracts to Base, Arbitrum, and Polygon Mainnets.
*   **$OPL Token Launch:** Initial distribution to early contributors and "Whistleblower" testers.
*   **Enterprise SDK:** A specialized SDK for legal teams to automate "License Procurement."
*   **ISO/SPDX Submission:** Apply for an official SPDX license identifier for OPL-1.1.

---

### How to Contribute
We are a zero-budget initiative driven by the belief that AI companies must pay for the code they extract.
*   **Legal:** Review the license text in `open-pact/license`.
*   **Dev:** Help us deploy to new chains (Solana/Rust port requests welcome!).
*   **Adopt:** Switch your project to OPL-1.1 and become a founding member of the Standard.

*Last Updated: April 2026*

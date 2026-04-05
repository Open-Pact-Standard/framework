# Open-Pact Roadmap

This document outlines the development path for the Open-Pact Framework and License. Our philosophy is **Trust First**: we verify the legal standard, we test the code on Testnet, and we engage the community before asking for real money.

## Phase 1: The Standard & Soft Launch (Current)
**Status: 🟢 Complete / Active**
*   **Goal:** Establish the license as a credible "Third Way" between MIT and Proprietary.
*   [x] **v1.1 Release:** Public launch of OPL-1.1 with Sunset, Whistleblower, and AI clauses.
*   [x] **Repository Structure:** Separate legal text (`license`) from code (`framework`).
*   [ ] **Community Review:** Gather feedback from developers and legal experts regarding Section 4 (AI Training) and Section 16 (Sunset).
*   [ ] **Reference Implementation:** Showcase the Gold DAO as a working example of a "Guild."

## Phase 2: Alpha Tooling & Testnet (Q3 2026)
**Status: 🔵 Planned**
*   **Goal:** Prove the technical enforcement mechanisms work without financial risk.
*   **Coston2 Deployment:** Deploy `RoyaltyRegistry` and `GuildRoyalty` to the Flare Coston2 Testnet.
*   **Guild Registry Dashboard:** Build a simple web interface where users can check if a company/developer holds a valid license.
*   **AI Audit Agent V1:** Release the Python-based `OPLAuditAgent` that scans GitHub for "Canary Strings" and cross-references them with the Testnet Registry.
*   **First Reference Guilds:** Onboard 2-3 independent open-source projects to switch to OPL-1.1 to test the governance model.

## Phase 3: Enforcement & Audits (Q4 2026)
**Status: ⚪ Upcoming**
*   **Goal:** Professional security review and robust enforcement.
*   **Smart Contract Audit:** Commission a professional audit for the `RoyaltyRegistry` and `Whistleblower` contracts.
*   **Whistleblower Fund Mechanics:** Test the "Bounty Payout" flow. Simulate a violation and reward a "reporter" (play money) to prove the incentive works.
*   **CI/CD Integration:** Release a GitHub Action (`open-pact-check`) that allows companies to automatically scan their dependencies for OPL compliance.
*   **Token Economics (Draft):** Finalize the whitepaper for the **$OPL Token** — strictly for use as a utility currency for AI Agents to pay for data/bounties, not for VC speculation.

## Phase 4: Mainnet & Ecosystem (Q1 2027)
**Status: ⚪ Future**
*   **Goal:** Full public launch and commercial adoption.
*   **Mainnet Deployment:** Deploy final audited contracts to Flare Mainnet (or chosen L2).
*   **$OPL Token Launch:** Initial distribution to early contributors and "Whistleblower" testers.
*   **Enterprise SDK:** A specialized SDK for legal teams to automate "License Procurement" and manage their OPL obligations.
*   **ISO/SPDX Submission:** Apply for an official SPDX license identifier for OPL-1.1 to make it a recognized standard.

---

### How to Contribute
We are a zero-budget initiative driven by the belief that AI companies must pay for the code they extract.
*   **Legal:** Review the license text in `open-pact/license` and submit issues for improvements.
*   **Dev:** Help us refine the `AuditAgent` or `RoyaltyRegistry` contracts in `open-pact/framework`.
*   **Adopt:** Switch your project to OPL-1.1 and become a founding member of the Standard.

*Last Updated: April 2026*

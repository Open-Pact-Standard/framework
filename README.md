# Open-Pact Framework

Smart contracts, AI audit tools, and reference implementations for the [Open-Pact License](https://github.com/Open-Pact-Standard/license).

## ⚠️ Status: Alpha / Unaudited
This repository contains early-stage implementations of the OPL-1.1 royalty and governance system.
It is provided **as-is** for testing, research, and integration prototyping. **Do not deploy to mainnet with real funds until a professional audit is completed.**

## Structure
- `core/contracts/` — RoyaltyRegistry, LicenseIssuer, GuildRoyalty, LicenseVerifier
- `reference-dao/` — A working DAO that integrates with the royalty system
- `docs/` — Fingerprinting & Enforcement Mechanic design documents

## License
The contracts are licensed under MIT for developer adoption. The software they protect is licensed under [OPL-1.1](https://github.com/Open-Pact-Standard/license).

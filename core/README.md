# Open-Pact Core

The core licensing and royalty infrastructure for the Open-Pact Framework.

## Contracts

### RoyaltyRegistry
The heart of the system. Collects license fees and distributes them to contributors based on weights.

### LicenseIssuer
The user-facing entry point for purchasing licenses. Handles ERC20 payments and acknowledgment data.

### LicenseVerifier
A stateless utility for checking if a specific entity has a valid license for a project.

### GuildRoyalty
The governance layer. Replaces single-maintainer control with Guild/Dao governance for setting fees and weights.

# Reference DAO - Gold DAO

This is a reference implementation of a DAO built on the Open-Pact Framework.
It demonstrates how to integrate the **RoyaltyRegistry**, **GuildRoyalty**, and other smart contracts into a real-world project.

## Contracts

- `governance/`: Token, Governor, Timelock
- `payments/`: Legacy marketplace and payment contracts (integrates with RoyaltyRegistry)
- `treasury/`: Management of funds

## How it works

The DAO serves as the "Guild" for its projects.
1. It deploys a `RoyaltyRegistry`.
2. It uses `GuildRoyalty` to govern the registry parameters.
3. Commercial users pay the DAO treasury via the registry.

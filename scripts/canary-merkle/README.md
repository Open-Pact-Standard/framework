# OPL-1.1 Canary Token System
## Commit-Reveal + Merkle Tree Design

### Overview

This directory contains the on-chain registry and off-chain tools for
OPL-1.1 Canary Token Enforcement (Section 11.2(e)). The system uses a
**commit-reveal scheme with Merkle trees** to store canary token
commitments on-chain WITHOUT exposing the actual canary values, embedding
locations, or detection methodology.

### Why Commit-Reveal?

Without it:
- On-chain canary data reveals detection methodology
- Adversaries learn patterns and strip tokens from code
- Adversaries can generate false match claims (planted evidence)

With commit-reveal + Merkle:
- On-chain data is opaque (just hash roots)
- Methodology stays entirely off-chain
- Enforcement claims are cryptographically verifiable
- Prevents both stripping AND planting attacks

### Architecture

```
OFF-CHAIN (Steward)                    ON-CHAIN (CanaryRegistry.sol)
====================                    ==============================
                                          
Generate canary secrets                 
  (variable names, dead code,           
   control-flow markers, etc.)          
          │                              
          ▼                              
Embed secrets in source distribution ──► registerDistribution()
                                          ├─ projectId
                                          ├─ distributionId
                                          ├─ merkleRoot (only!)
                                          └─ issuedTo
                                          
When canary found in unauthorized code:
  1. Extract canarySecret from code     
  2. Look up distribution               ──► reportCanaryMatch()
  3. Generate Merkle proof                ├─ canarySecret (revealed!)
  4. Submit on-chain with               ├─ leafIndex
     evidence hash                       ├─ merkleProof
                                         └─ accusedParty, evidenceHash
                                          
                                         Any verifier can:
                                         ──► verifyCanary()
```

### File Structure

```
contracts/canary/
├── ICanaryRegistry.sol     # Interface (events, structs, functions)
└── CanaryRegistry.sol      # Implementation (commit-reveal + Merkle)

test/
└── CanaryRegistry.t.sol    # Comprehensive Foundry test suite

scripts/canary-merkle/
├── merkle-builder.js       # CLI: generate Merkle trees + proofs
└── README.md               # This file
```

### Steward Workflow

1. **Generate canaries**: Create unique, hard-to-guess strings to embed
   in each distribution of the OPL-licensed code. Each distribution gets
   a DIFFERENT set of canaries (different `distributionId` → different
   leaf hashes → different Merkle root).

2. **Embed in code**: Insert canary tokens into the source code using
   various techniques:
   - Obfuscated variable/function names
   - Dead code blocks that compile but do nothing
   - Control-flow markers in conditional branches  
   - Data watermarks in constants/strings

3. **Compute Merkle root**: Run `merkle-builder.js` with all canary
   secrets, `projectId`, and `distributionId`:
   ```bash
   node merkle-builder.js \
     --project 1 \
     --dist 0xabc123... \
     "var_x7f3a2b" \
     "if(_k8m9n) { return 0x42; }" \
     "dead_code_marker_c1d2e3f4"
   ```

4. **Register on-chain**: Call `CanaryRegistry.registerDistribution()`
   with the Merkle root. The individual secrets NEVER go on-chain.

5. **Enforce**: When a canary is found in unauthorized code:
   ```bash
   # Extract the canary from the infringing code
   canarySecret="var_x7f3a2b"
   leafIndex=0
   
   # Generate proof (reuse merkle-builder output or regenerate)
   proof=["0x...", "0x..."]
   
   # Submit on-chain with evidence hash (hash of code diff, etc.)
   # call reportCanaryMatch()
   ```

6. **Verify**: Anyone (including arbitrators) can independently verify
   the claim by calling `verifyCanary()` with the revealed secret and
   proof. A match proves the token was embedded at timestamp X in
   distribution Y.

### Security Properties

- **Immutability**: On-chain commitments cannot be altered
- **Non-repudiation**: Steward cannot change committed canaries
- **Selective reveal**: Only the matching canary is revealed during
  enforcement, not the entire set
- **Cross-distribution tracking**: If a canary from licensee A's
  distribution appears in licensee B's product, the chain of custody
  proves A's distribution was the source
- **Planting defense prevention**: Adversaries cannot claim tokens
  were planted after-the-fact because the commitment timestamp proves
  existence before the alleged infringement

#!/usr/bin/env node
/**
 * Merkle Tree Builder for OPL-1.1 Canary Tokens
 *
 * USAGE:
 *   node merkle-builder.js <canary1> <canary2> ... <canaryN>
 *
 * OUTPUT:
 *   {
 *     "merkleRoot": "0x...",
 *     "leafCount": N,
 *     "leaves": ["0x...", ...],
 *     "proofs": [
 *       ["0x...", "0x...", ...],   // Proof for leaf 0
 *       ["0x...", "0x...", ...],   // Proof for leaf 1
 *       ...
 *     ]
 *   }
 *
 * Each leaf = keccak256(canarySecret || projectId || distributionId || leafIndex)
 *
 * The merkleRoot is stored on-chain. Each proof is used during enforcement
 * to prove a specific canary belongs to the registered distribution.
 *
 * The steward keeps the canarySecrets and proofs OFF-CHAIN.
 */

const { createHash } = require('crypto');

function keccak256(buffer) {
    // Simple keccak256 via Node.js crypto (Note: real deployments should use
    // ethereum-cryptography/keccak for production)
    const hash = createHash('sha3-256');
    hash.update(buffer);
    return hash.digest();
}

function computeLeaf(canarySecret, projectId, distributionId, leafIndex) {
    const data = Buffer.concat([
        Buffer.from(canarySecret, 'utf8'),
        Buffer.from(String(projectId)),
        Buffer.from(distributionId.replace('0x', ''), 'hex'),
        Buffer.from(String(leafIndex))
    ]);
    return keccak256(data);
}

function buildMerkleTree(leafHashes) {
    if (leafHashes.length === 0) {
        throw new Error('At least one leaf required');
    }

    // Pad to power of 2
    const count = leafHashes.length;
    const nextPow2 = count <= 1 ? 1 : Math.pow(2, Math.ceil(Math.log2(count)));
    while (leafHashes.length < nextPow2) {
        // Duplicate last hash for padding
        leafHashes.push(Buffer.from(leafHashes[leafHashes.length - 1]));
    }

    // Build tree bottom-up
    let level = leafHashes.slice();
    const tree = [level];

    while (level.length > 1) {
        const nextLevel = [];
        for (let i = 0; i < level.length; i += 2) {
            const left = level[i];
            const right = level[i + 1];
            const parent = keccak256(Buffer.concat([left, right]));
            nextLevel.push(parent);
        }
        tree.push(nextLevel);
        level = nextLevel;
    }

    return tree;
}

function getMerkleProof(tree, leafIndex) {
    const proof = [];
    let index = leafIndex;

    for (let level = 0; level < tree.length - 1; level++) {
        const siblingIndex = index % 2 === 0 ? index + 1 : index - 1;
        const sibling = tree[level][siblingIndex];
        proof.push(sibling);
        index = Math.floor(index / 2);
    }

    return proof;
}

function bufToHex(buf) {
    return '0x' + buf.toString('hex');
}

// ================================================================
// MAIN CLI
// ================================================================

function main() {
    const args = process.argv.slice(2);

    if (args.length < 2) {
        console.error('Usage: node merkle-builder.js --project <id> --dist <hex_id> <canary1> <canary2> ...');
        console.error('');
        console.error('Options:');
        console.error('  --project <id>       OPL project ID');
        console.error('  --dist <hex>         Distribution ID (0x-prefixed hex)');
        console.error('  <canary1..N>         Canary token secret strings');
        console.error('');
        console.error('Example:');
        console.error('  node merkle-builder.js --project 1 --dist 0xabc123 "var_x7f3a" "dead_code_92c1"');
        process.exit(1);
    }

    let projectId = 0;
    let distId = '';
    const secrets = [];

    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--project') {
            projectId = parseInt(args[++i]);
        } else if (args[i] === '--dist') {
            distId = args[++i];
        } else {
            secrets.push(args[i]);
        }
    }

    if (projectId === 0 || distId === '' || secrets.length === 0) {
        console.error('Error: Missing required arguments');
        process.exit(1);
    }

    // Compute leaf hashes
    const leafHashes = secrets.map((secret, i) => computeLeaf(secret, projectId, distId, i));

    // Build Merkle tree
    const tree = buildMerkleTree(leafHashes);
    const root = tree[tree.length - 1][0];

    // Generate proofs
    const proofs = secrets.map((_, i) => getMerkleProof(tree, i));

    const output = {
        projectId: projectId,
        distributionId: distId,
        merkleRoot: bufToHex(root),
        leafCount: secrets.length,
        secrets: secrets,
        leaves: leafHashes.map(bufToHex),
        proofs: proofs.map(p => p.map(bufToHex))
    };

    console.log(JSON.stringify(output, null, 2));
}

main();

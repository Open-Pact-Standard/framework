"""
OPL Audit Agent v0.1 (Proof of Concept)

This tool scans public repositories for usage of OPL-licensed Software.
It detects specific "Canary Strings" or the License File itself.
It then cross-references the discovery with the Guild's License Registry.

DISCLAIMER: This is a tool for the Guild to monitor compliance.
"""

import os
import json
import hashlib
from datetime import datetime

# ============================================================
# CONFIGURATION
# ============================================================

# The "Canary String" - A unique hex/comment string embedded in the source code.
# In a real scenario, this is injected into binary artifacts or unique comments.
CANARY_STRING_V1 = "OPL_CANARY_V1: [0x98A4...]" 
LICENSE_FILE_NAME = "LICENSE.md"
LICENSE_HASH = "SHA256_HASH_OF_OPL_1.1_TEXT_HERE" # Placeholder for actual hash

# Mock Registry (Simulating the Blockchain API)
# In production, this connects to the RoyaltyRegistry.sol contract
MOCK_REGISTRY = {
    "AcmeCorp": {"status": "VERIFIED", "tier": "Commercial", "expiry": "2026-12-31"},
    "EvilAI_Inc": {"status": "NONE", "tier": "None", "expiry": "N/A"}
}

# ============================================================
# THE AGENT
# ============================================================

class OPLAuditAgent:
    def __init__(self, github_token=None):
        print(f"🤖 OPL Audit Agent Initialized.")
        self.violations = []
        self.compliant_users = set()

    def scan_github_repo(self, username, repo_files):
        """Simulate scanning a user's repository for Canary Strings."""
        found_canary = False
        found_license = False

        for filename, content in repo_files.items():
            # 1. Check for Canary String
            if CANARY_STRING_V1 in content:
                print(f"   🕵️‍♂️ [DETECTION] Found Canary in {filename}")
                found_canary = True
            
            # 2. Check for OPL License File
            if filename == LICENSE_FILE_NAME:
                # Check if it looks like OPL (simplified check)
                if "Open-Pact License" in content:
                    print(f"   🕵️‍♂️ [DETECTION] Found OPL-1.1 License file")
                    found_license = True

        if found_canary or found_license:
            print(f"   ✅ Software Detected in @{username}'s repo.")
            return True
        return False

    def check_registry(self, entity_name):
        """Simulate querying the On-Chain Registry via API."""
        print(f"   🔗 Checking Registry for '{entity_name}'...")
        
        status = MOCK_REGISTRY.get(entity_name, {"status": "UNKNOWN", "tier": "Unknown"})
        
        if status["status"] in ["VERIFIED", "ACTIVE"]:
            print(f"   🟢 Status: {status['status']} (Tier: {status['tier']})")
            return True
        else:
            print(f"   🔴 Status: {status['status']} (NO LICENSE FOUND)")
            return False

    def process_violation(self, entity_name, reason):
        """Record a violation for the Guild to pursue."""
        violation = {
            "entity": entity_name,
            "reason": reason,
            "timestamp": datetime.now().isoformat(),
            "action": "ISSUE_AMNESTY_NOTICE" # Section 17.4
        }
        self.violations.append(violation)

    def run_audit(self, targets):
        """Run the full audit loop."""
        print("\n🚀 Starting OPL Compliance Audit...\n")
        
        for username, repo_data in targets.items():
            print(f"📦 Scanning @{username}...")
            
            detected = self.scan_github_repo(username, repo_data['files'])
            
            if detected:
                licensed = self.check_registry(repo_data['registry_name'])
                
                if not licensed:
                    print(f"   ⚠️ VIOLATION: {username} is using OPL code without a license.")
                    self.process_violation(
                        username, 
                        "Detected usage of OPL Source without valid License Record."
                    )
                else:
                    self.compliant_users.add(username)
            print("-" * 40)

    def generate_report(self):
        """Generate a formal enforcement report."""
        print("\n📊 AUDIT REPORT")
        print("=" * 40)
        print(f"✅ Compliant Entities: {len(self.compliant_users)}")
        print(f"⚠️ Violations Detected: {len(self.violations)}")
        
        if self.violations:
            print("\n⚖️ REQUIRED ENFORCEMENT ACTIONS:")
            for v in self.violations:
                print(f"   - Target: {v['entity']}")
                print(f"     Reason: {v['reason']}")
                print(f"     Action: Send 'Amnesty Notice' (Section 17.4)")
        
        return self.violations

# ============================================================
# EXECUTION
# ============================================================

if __name__ == "__main__":
    # 1. Initialize Agent
    agent = OPLAuditAgent()

    # 2. Define Targets (Simulated Data from GitHub Scrape)
    # 'registry_name' is the name registered in the Smart Contract
    simulated_targets = {
        "GoodDev_Studio": {
            "registry_name": "GoodDev_Studio",
            "files": {
                "main.py": "print('Hello World')\n# OPL_CANARY_V1: [0x98A4...]\nimport open_pact_lib"
            }
        },
        "AcmeCorp_SaaS": {
            "registry_name": "AcmeCorp",
            "files": {
                "backend.js": "// Internal SaaS\n// OPL_CANARY_V1: [0x98A4...]\nconst { registry } = require('@open-pact/core');"
            }
        },
        "EvilAI_StealthMode": {
            "registry_name": "EvilAI_Inc", 
            "files": {
                "model_trainer.py": "# Loading training data...\nimport open_pact_utils # OPL_CANARY_V1: [0x98A4...]"
            }
        },
        "Random_User": {
            "registry_name": "Unknown_Individual",
            "files": {
                "script.py": "print('I just copied the OPL License file into my project')"
            }
        }
    }

    # 3. Run Audit
    agent.run_audit(simulated_targets)
    
    # 4. Generate Report
    violations = agent.generate_report()

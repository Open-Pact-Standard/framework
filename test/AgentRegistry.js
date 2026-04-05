const { expect } = require("chai");
const hre = require("hardhat");

// Use hre.ethers directly instead of global
const ethers = hre.ethers;

describe("IdentityRegistry", function () {
  let identityRegistry;
  let owner, user1, user2;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    owner = signers[0];
    user1 = signers[1];
    user2 = signers[2];
    
    const IdentityRegistry = await ethers.getContractFactory("IdentityRegistry");
    identityRegistry = await IdentityRegistry.deploy();
    await identityRegistry.waitForDeployment();
  });

  describe("Registration", function () {
    it("should allow user to register with URI", async function () {
      const tx = await identityRegistry.connect(user1).register("ipfs://QmTest123");
      await tx.wait();
      
      const agentId = await identityRegistry.getAgentId(user1.address);
      expect(agentId).to.be.gt(0);
    });

    it("should not allow duplicate registration", async function () {
      await identityRegistry.connect(user1).register("ipfs://QmTest123");
      
      await expect(
        identityRegistry.connect(user1).register("ipfs://QmTest456")
      ).to.be.revertedWith("IdentityRegistry: wallet already registered");
    });

    it("should return correct agent wallet", async function () {
      await identityRegistry.connect(user1).register("ipfs://QmTest123");
      const agentId = await identityRegistry.getAgentId(user1.address);
      
      const wallet = await identityRegistry.getAgentWallet(agentId);
      expect(wallet).to.equal(user1.address);
    });

    it("should track total agents", async function () {
      await identityRegistry.connect(user1).register("ipfs://QmTest1");
      await identityRegistry.connect(user2).register("ipfs://QmTest2");
      
      const total = await identityRegistry.getTotalAgents();
      expect(total).to.equal(2);
    });
  });

  describe("Wallet Changes", function () {
    it("should allow wallet change", async function () {
      await identityRegistry.connect(user1).register("ipfs://QmTest123");
      const agentId = await identityRegistry.getAgentId(user1.address);
      
      await identityRegistry.connect(user1).setAgentWallet(user2.address);
      
      const newWallet = await identityRegistry.getAgentWallet(agentId);
      expect(newWallet).to.equal(user2.address);
    });
  });
});

describe("ReputationRegistry", function () {
  let reputationRegistry;
  let owner, reviewer1, reviewer2;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    owner = signers[0];
    reviewer1 = signers[1];
    reviewer2 = signers[2];
    
    const ReputationRegistry = await ethers.getContractFactory("ReputationRegistry");
    reputationRegistry = await ReputationRegistry.deploy();
    await reputationRegistry.waitForDeployment();
  });

  describe("Reviews", function () {
    it("should allow submitting a review", async function () {
      await reputationRegistry.connect(reviewer1).submitReview(1, 8, "Great agent!");
    });

    it("should calculate correct reputation", async function () {
      await reputationRegistry.connect(reviewer1).submitReview(1, 8, "Great!");
      await reputationRegistry.connect(reviewer2).submitReview(1, 4, "Okay");
      
      const reputation = await reputationRegistry.getReputation(1);
      expect(reputation).to.equal(6);
    });

    it("should track review count", async function () {
      await reputationRegistry.connect(reviewer1).submitReview(1, 5, "Review 1");
      await reputationRegistry.connect(reviewer2).submitReview(1, 7, "Review 2");
      
      const count = await reputationRegistry.getReviewCount(1);
      expect(count).to.equal(2);
    });

    it("should reject score out of range", async function () {
      await expect(
        reputationRegistry.connect(reviewer1).submitReview(1, 15, "Too high")
      ).to.be.revertedWith("ReputationRegistry: score out of range");
    });
  });
});

describe("ValidationRegistry", function () {
  let validationRegistry;
  let owner, validator1, validator2;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    owner = signers[0];
    validator1 = signers[1];
    validator2 = signers[2];
    
    const ValidationRegistry = await ethers.getContractFactory("ValidationRegistry");
    validationRegistry = await ValidationRegistry.deploy();
    await validationRegistry.waitForDeployment();
  });

  describe("Validators", function () {
    it("should allow registration as validator", async function () {
      await validationRegistry.connect(validator1).registerValidator();
      
      const isValidator = await validationRegistry.isValidator(validator1.address);
      expect(isValidator).to.be.true;
    });

    it("should validate agent", async function () {
      await validationRegistry.connect(validator1).registerValidator();
      await validationRegistry.connect(validator1).validateAgent(1, true);
      
      const isValidated = await validationRegistry.isAgentValidated(1);
      expect(isValidated).to.be.true;
    });

    it("should track validation count", async function () {
      await validationRegistry.connect(validator1).registerValidator();
      await validationRegistry.connect(validator1).validateAgent(1, true);
      
      const count = await validationRegistry.getValidationCount(1);
      expect(count).to.equal(1);
    });

    it("should require validator role to validate", async function () {
      await expect(
        validationRegistry.connect(owner).validateAgent(1, true)
      ).to.be.revertedWith("ValidationRegistry: not a validator");
    });
  });
});

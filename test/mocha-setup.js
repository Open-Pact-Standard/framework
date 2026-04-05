// Mocha hooks file - provides globals for tests
const hre = require("hardhat");

before(async function () {
  // Provide ethers globally like hardhat-toolbox does
  global.ethers = hre.ethers;
});

beforeEach(async function () {
  // Ensure ethers is available in each test
  if (!global.ethers) {
    global.ethers = hre.ethers;
  }
});

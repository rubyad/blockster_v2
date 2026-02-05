const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("BuxBoosterGame V7 - Separated BUX Stats", function () {
  let BuxBoosterGame;
  let buxBoosterGame;
  let mockToken;
  let owner;
  let settler;
  let player1;
  let player2;

  // Constants from the contract
  const MIN_BET = ethers.parseEther("1"); // 1 token
  const DIFFICULTY_SINGLE_FLIP = 1; // Index 4 in array, 1.98x multiplier
  const MULTIPLIER_SINGLE_FLIP = 19800; // 1.98x in basis points

  beforeEach(async function () {
    [owner, settler, player1, player2] = await ethers.getSigners();

    // Deploy a mock ERC20 token for BUX
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("Mock BUX", "BUX", 18);
    await mockToken.waitForDeployment();

    // Mint tokens to players and house
    await mockToken.mint(player1.address, ethers.parseEther("10000"));
    await mockToken.mint(player2.address, ethers.parseEther("10000"));

    // Deploy BuxBoosterGame as upgradeable proxy
    BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
    buxBoosterGame = await upgrades.deployProxy(
      BuxBoosterGame,
      [],
      { initializer: "initialize" }
    );
    await buxBoosterGame.waitForDeployment();

    // Initialize V2 (sets multipliers and flip counts)
    await buxBoosterGame.initializeV2();

    // Set settler
    await buxBoosterGame.setSettler(settler.address);

    // Enable BUX token and deposit house balance
    const tokenAddress = await mockToken.getAddress();
    const contractAddress = await buxBoosterGame.getAddress();

    // Configure token as enabled
    await buxBoosterGame.configureToken(tokenAddress, true);

    // Mint tokens to owner, approve, then deposit as house balance
    await mockToken.mint(owner.address, ethers.parseEther("100000"));
    await mockToken.connect(owner).approve(contractAddress, ethers.parseEther("100000"));
    await buxBoosterGame.depositHouseBalance(tokenAddress, ethers.parseEther("100000"));

    // Approve tokens for players
    await mockToken.connect(player1).approve(await buxBoosterGame.getAddress(), ethers.MaxUint256);
    await mockToken.connect(player2).approve(await buxBoosterGame.getAddress(), ethers.MaxUint256);
  });

  describe("V7 Initialization", function () {
    it("Should initialize V7 successfully", async function () {
      await buxBoosterGame.initializeV7();
      // If it doesn't revert, initialization succeeded
    });

    it("Should reject double initialization of V7", async function () {
      await buxBoosterGame.initializeV7();
      await expect(buxBoosterGame.initializeV7()).to.be.revertedWithCustomError(
        buxBoosterGame,
        "InvalidInitialization"
      );
    });

    it("Should start with zero BUX accounting", async function () {
      await buxBoosterGame.initializeV7();

      const accounting = await buxBoosterGame.getBuxAccounting();
      expect(accounting[0]).to.equal(0n); // totalBets
      expect(accounting[1]).to.equal(0n); // totalWins
      expect(accounting[2]).to.equal(0n); // totalLosses
      expect(accounting[3]).to.equal(0n); // totalVolumeWagered
      expect(accounting[4]).to.equal(0n); // totalPayouts
      expect(accounting[5]).to.equal(0n); // totalHouseProfit
      expect(accounting[6]).to.equal(0n); // largestWin
      expect(accounting[7]).to.equal(0n); // largestBet
    });

    it("Should start with zero player stats", async function () {
      await buxBoosterGame.initializeV7();

      const stats = await buxBoosterGame.getBuxPlayerStats(player1.address);
      expect(stats[0]).to.equal(0n); // totalBets
      expect(stats[1]).to.equal(0n); // wins
      expect(stats[2]).to.equal(0n); // losses
      expect(stats[3]).to.equal(0n); // totalWagered
      expect(stats[4]).to.equal(0n); // totalWinnings
      expect(stats[5]).to.equal(0n); // totalLosses
    });
  });

  describe("BUX Stats Tracking on Settlement", function () {
    let commitmentHash;
    let tokenAddress;
    const betAmount = ethers.parseEther("100");
    const serverSeed = "0x" + "a".repeat(64);

    beforeEach(async function () {
      await buxBoosterGame.initializeV7();

      tokenAddress = await mockToken.getAddress();

      // Create a commitment for the bet
      commitmentHash = ethers.keccak256(ethers.toUtf8Bytes(serverSeed));

      // Submit commitment (order: commitmentHash, player, nonce)
      await buxBoosterGame.connect(settler).submitCommitment(
        commitmentHash,
        player1.address,
        0 // nonce
      );
    });

    it("Should update BUX player stats on winning bet", async function () {
      // Place bet (token, amount, difficulty, predictions, commitmentHash)
      await buxBoosterGame.connect(player1).placeBet(
        tokenAddress,
        betAmount,
        1, // difficulty (single flip, 1.98x)
        [0], // predictions (heads)
        commitmentHash
      );

      // Settle as win
      await buxBoosterGame.connect(settler).settleBet(
        commitmentHash,
        serverSeed,
        [0], // results (heads - matches prediction)
        true // won
      );

      const stats = await buxBoosterGame.getBuxPlayerStats(player1.address);
      expect(stats[0]).to.equal(1n); // totalBets
      expect(stats[1]).to.equal(1n); // wins
      expect(stats[2]).to.equal(0n); // losses
      expect(stats[3]).to.equal(betAmount); // totalWagered
      expect(stats[4]).to.be.gt(0n); // totalWinnings (profit)
      expect(stats[5]).to.equal(0n); // totalLosses
    });

    it("Should update BUX player stats on losing bet", async function () {
      // Place bet
      await buxBoosterGame.connect(player1).placeBet(
        tokenAddress,
        betAmount,
        1, // difficulty (single flip, 1.98x)
        [0], // predictions (heads)
        commitmentHash
      );

      // Settle as loss
      await buxBoosterGame.connect(settler).settleBet(
        commitmentHash,
        serverSeed,
        [1], // results (tails - doesn't match prediction)
        false // lost
      );

      const stats = await buxBoosterGame.getBuxPlayerStats(player1.address);
      expect(stats[0]).to.equal(1n); // totalBets
      expect(stats[1]).to.equal(0n); // wins
      expect(stats[2]).to.equal(1n); // losses
      expect(stats[3]).to.equal(betAmount); // totalWagered
      expect(stats[4]).to.equal(0n); // totalWinnings
      expect(stats[5]).to.equal(betAmount); // totalLosses
    });

    it("Should update BUX global accounting on win", async function () {
      // Place bet
      await buxBoosterGame.connect(player1).placeBet(
        tokenAddress,
        betAmount,
        1,
        [0],
        commitmentHash
      );

      // Settle as win
      await buxBoosterGame.connect(settler).settleBet(
        commitmentHash,
        serverSeed,
        [0],
        true
      );

      const accounting = await buxBoosterGame.getBuxAccounting();
      expect(accounting[0]).to.equal(1n); // totalBets
      expect(accounting[1]).to.equal(1n); // totalWins
      expect(accounting[2]).to.equal(0n); // totalLosses
      expect(accounting[3]).to.equal(betAmount); // totalVolumeWagered
      expect(accounting[4]).to.be.gt(betAmount); // totalPayouts (bet + profit)
      expect(accounting[5]).to.be.lt(0n); // totalHouseProfit (negative = house loss)
    });

    it("Should update BUX global accounting on loss", async function () {
      // Place bet
      await buxBoosterGame.connect(player1).placeBet(
        tokenAddress,
        betAmount,
        1,
        [0],
        commitmentHash
      );

      // Settle as loss
      await buxBoosterGame.connect(settler).settleBet(
        commitmentHash,
        serverSeed,
        [1],
        false
      );

      const accounting = await buxBoosterGame.getBuxAccounting();
      expect(accounting[0]).to.equal(1n); // totalBets
      expect(accounting[1]).to.equal(0n); // totalWins
      expect(accounting[2]).to.equal(1n); // totalLosses
      expect(accounting[3]).to.equal(betAmount); // totalVolumeWagered
      expect(accounting[4]).to.equal(0n); // totalPayouts
      expect(accounting[5]).to.equal(BigInt(betAmount)); // totalHouseProfit (positive = house win)
    });

    it("Should track largest bet correctly", async function () {
      const smallBet = ethers.parseEther("10");
      const largeBet = ethers.parseEther("50");

      // First bet - small
      const seed1 = "0x" + "b".repeat(64);
      const hash1 = ethers.keccak256(ethers.toUtf8Bytes(seed1));
      await buxBoosterGame.connect(settler).submitCommitment(hash1, player1.address, 0);
      await buxBoosterGame.connect(player1).placeBet(tokenAddress, smallBet, 1, [0], hash1);
      await buxBoosterGame.connect(settler).settleBet(hash1, seed1, [1], false);

      let accounting = await buxBoosterGame.getBuxAccounting();
      expect(accounting[7]).to.equal(smallBet); // largestBet

      // Second bet - larger
      const seed2 = "0x" + "c".repeat(64);
      const hash2 = ethers.keccak256(ethers.toUtf8Bytes(seed2));
      await buxBoosterGame.connect(settler).submitCommitment(hash2, player1.address, 1);
      await buxBoosterGame.connect(player1).placeBet(tokenAddress, largeBet, 1, [0], hash2);
      await buxBoosterGame.connect(settler).settleBet(hash2, seed2, [1], false);

      accounting = await buxBoosterGame.getBuxAccounting();
      expect(accounting[7]).to.equal(largeBet); // largestBet updated
    });

    it("Should track per-difficulty stats", async function () {
      // Place bet at difficulty 1 (single flip)
      await buxBoosterGame.connect(player1).placeBet(
        tokenAddress,
        betAmount,
        1,
        [0],
        commitmentHash
      );

      await buxBoosterGame.connect(settler).settleBet(
        commitmentHash,
        serverSeed,
        [1],
        false
      );

      const stats = await buxBoosterGame.getBuxPlayerStats(player1.address);
      // betsPerDifficulty[4] should be 1 (difficulty 1 maps to index 4)
      expect(stats[6][4]).to.equal(1n);
      // profitLossPerDifficulty[4] should be negative (loss)
      expect(stats[7][4]).to.equal(-BigInt(betAmount));
    });
  });

  describe("Multiple Players", function () {
    let tokenAddress;

    beforeEach(async function () {
      await buxBoosterGame.initializeV7();
      tokenAddress = await mockToken.getAddress();
    });

    it("Should track stats separately for each player", async function () {
      const betAmount = ethers.parseEther("100");

      // Player 1 bet
      const seed1 = "0x" + "d".repeat(64);
      const hash1 = ethers.keccak256(ethers.toUtf8Bytes(seed1));
      await buxBoosterGame.connect(settler).submitCommitment(hash1, player1.address, 0);
      await buxBoosterGame.connect(player1).placeBet(tokenAddress, betAmount, 1, [0], hash1);
      await buxBoosterGame.connect(settler).settleBet(hash1, seed1, [0], true); // win

      // Player 2 bet
      const seed2 = "0x" + "e".repeat(64);
      const hash2 = ethers.keccak256(ethers.toUtf8Bytes(seed2));
      await buxBoosterGame.connect(settler).submitCommitment(hash2, player2.address, 0);
      await buxBoosterGame.connect(player2).placeBet(tokenAddress, betAmount, 1, [0], hash2);
      await buxBoosterGame.connect(settler).settleBet(hash2, seed2, [1], false); // loss

      // Check player 1 stats
      const stats1 = await buxBoosterGame.getBuxPlayerStats(player1.address);
      expect(stats1[0]).to.equal(1n); // totalBets
      expect(stats1[1]).to.equal(1n); // wins
      expect(stats1[2]).to.equal(0n); // losses

      // Check player 2 stats
      const stats2 = await buxBoosterGame.getBuxPlayerStats(player2.address);
      expect(stats2[0]).to.equal(1n); // totalBets
      expect(stats2[1]).to.equal(0n); // wins
      expect(stats2[2]).to.equal(1n); // losses

      // Check global accounting includes both
      const accounting = await buxBoosterGame.getBuxAccounting();
      expect(accounting[0]).to.equal(2n); // totalBets
      expect(accounting[1]).to.equal(1n); // totalWins
      expect(accounting[2]).to.equal(1n); // totalLosses
    });
  });

  describe("Old Stats Preservation", function () {
    it("Should not write to old playerStats mapping", async function () {
      await buxBoosterGame.initializeV7();

      const betAmount = ethers.parseEther("100");
      const seed = "0x" + "f".repeat(64);
      const hash = ethers.keccak256(ethers.toUtf8Bytes(seed));
      const tokenAddress = await mockToken.getAddress();

      // Get old stats before
      const oldStatsBefore = await buxBoosterGame.getPlayerStats(player1.address);

      // Place and settle bet
      await buxBoosterGame.connect(settler).submitCommitment(hash, player1.address, 0);
      await buxBoosterGame.connect(player1).placeBet(tokenAddress, betAmount, 1, [0], hash);
      await buxBoosterGame.connect(settler).settleBet(hash, seed, [1], false);

      // Get old stats after - should be unchanged
      const oldStatsAfter = await buxBoosterGame.getPlayerStats(player1.address);
      expect(oldStatsAfter[0]).to.equal(oldStatsBefore[0]); // totalBets unchanged
      expect(oldStatsAfter[1]).to.equal(oldStatsBefore[1]); // totalStaked unchanged

      // New stats should be updated
      const newStats = await buxBoosterGame.getBuxPlayerStats(player1.address);
      expect(newStats[0]).to.equal(1n); // totalBets updated
    });
  });
});

// Mock ERC20 contract for testing
// This would normally be in a separate file
const MockERC20Artifact = {
  abi: [
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function totalSupply() view returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
    "function transfer(address, uint256) returns (bool)",
    "function allowance(address, address) view returns (uint256)",
    "function approve(address, uint256) returns (bool)",
    "function transferFrom(address, address, uint256) returns (bool)",
    "function mint(address, uint256)"
  ]
};

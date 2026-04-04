const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("NFTRewarder", function () {
  let NFTRewarder;
  let nftRewarder;
  let owner;
  let admin;
  let rogueBankroll;
  let user1;
  let user2;
  let user3;

  // Multipliers per hostess type
  const MULTIPLIERS = [100, 90, 80, 70, 60, 50, 40, 30];
  const HOSTESS_NAMES = ["Penelope", "Mia", "Cleo", "Sophia", "Luna", "Aurora", "Scarlett", "Vivienne"];

  beforeEach(async function () {
    [owner, admin, rogueBankroll, user1, user2, user3] = await ethers.getSigners();

    NFTRewarder = await ethers.getContractFactory("NFTRewarder");
    nftRewarder = await upgrades.deployProxy(
      NFTRewarder,
      [],
      { initializer: "initialize" }
    );
    await nftRewarder.waitForDeployment();

    // Set admin and rogueBankroll after deployment
    await nftRewarder.setAdmin(admin.address);
    await nftRewarder.setRogueBankroll(rogueBankroll.address);
  });

  describe("Initialization", function () {
    it("Should set the right owner", async function () {
      expect(await nftRewarder.owner()).to.equal(owner.address);
    });

    it("Should set the right admin", async function () {
      expect(await nftRewarder.admin()).to.equal(admin.address);
    });

    it("Should set the right rogueBankroll", async function () {
      expect(await nftRewarder.rogueBankroll()).to.equal(rogueBankroll.address);
    });

    it("Should start with zero registered NFTs", async function () {
      expect(await nftRewarder.totalRegisteredNFTs()).to.equal(0);
      expect(await nftRewarder.totalMultiplierPoints()).to.equal(0);
    });

    it("Should reject zero admin address", async function () {
      // After deployment, trying to set zero address as admin should fail
      const NFTRewarder2 = await ethers.getContractFactory("NFTRewarder");
      const rewarder2 = await upgrades.deployProxy(NFTRewarder2, [], { initializer: "initialize" });
      await rewarder2.waitForDeployment();

      await expect(
        rewarder2.setAdmin(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(rewarder2, "InvalidAddress");
    });
  });

  describe("Access Control", function () {
    it("Should allow owner to change admin", async function () {
      await nftRewarder.setAdmin(user1.address);
      expect(await nftRewarder.admin()).to.equal(user1.address);
    });

    it("Should reject non-owner changing admin", async function () {
      await expect(
        nftRewarder.connect(user1).setAdmin(user2.address)
      ).to.be.revertedWithCustomError(nftRewarder, "OwnableUnauthorizedAccount");
    });

    it("Should allow owner to change rogueBankroll", async function () {
      await nftRewarder.setRogueBankroll(user1.address);
      expect(await nftRewarder.rogueBankroll()).to.equal(user1.address);
    });

    it("Should reject non-owner changing rogueBankroll", async function () {
      await expect(
        nftRewarder.connect(user1).setRogueBankroll(user2.address)
      ).to.be.revertedWithCustomError(nftRewarder, "OwnableUnauthorizedAccount");
    });
  });

  describe("NFT Registration", function () {
    it("Should register an NFT with correct metadata", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address); // Penelope (100x)

      const metadata = await nftRewarder.getNFTMetadata(1);
      expect(metadata.hostessIndex).to.equal(0);
      expect(metadata.registered).to.equal(true);
      expect(metadata._owner).to.equal(user1.address);
      expect(metadata.multiplier).to.equal(100);
    });

    it("Should update totalRegisteredNFTs", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address);
      expect(await nftRewarder.totalRegisteredNFTs()).to.equal(1);

      await nftRewarder.connect(admin).registerNFT(2, 1, user1.address);
      expect(await nftRewarder.totalRegisteredNFTs()).to.equal(2);
    });

    it("Should update totalMultiplierPoints correctly", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address); // 100
      expect(await nftRewarder.totalMultiplierPoints()).to.equal(100);

      await nftRewarder.connect(admin).registerNFT(2, 7, user1.address); // 30
      expect(await nftRewarder.totalMultiplierPoints()).to.equal(130);
    });

    it("Should reject invalid hostess index", async function () {
      await expect(
        nftRewarder.connect(admin).registerNFT(1, 8, user1.address)
      ).to.be.revertedWithCustomError(nftRewarder, "InvalidHostessIndex");
    });

    it("Should reject duplicate registration", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address);
      await expect(
        nftRewarder.connect(admin).registerNFT(1, 0, user1.address)
      ).to.be.revertedWithCustomError(nftRewarder, "AlreadyRegistered");
    });

    it("Should reject non-admin registration", async function () {
      await expect(
        nftRewarder.connect(user1).registerNFT(1, 0, user1.address)
      ).to.be.revertedWithCustomError(nftRewarder, "NotAdmin");
    });

    it("Should emit NFTRegistered event", async function () {
      await expect(nftRewarder.connect(admin).registerNFT(1, 0, user1.address))
        .to.emit(nftRewarder, "NFTRegistered")
        .withArgs(1, user1.address, 0);
    });
  });

  describe("Batch Registration", function () {
    it("Should batch register multiple NFTs", async function () {
      const tokenIds = [1, 2, 3, 4];
      const hostessIndices = [0, 1, 2, 3];
      const owners = [user1.address, user1.address, user2.address, user2.address];

      await nftRewarder.connect(admin).batchRegisterNFTs(tokenIds, hostessIndices, owners);

      expect(await nftRewarder.totalRegisteredNFTs()).to.equal(4);
      // 100 + 90 + 80 + 70 = 340
      expect(await nftRewarder.totalMultiplierPoints()).to.equal(340);
    });

    it("Should skip already registered NFTs in batch", async function () {
      // Register one first
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address);

      // Batch includes the already registered one
      const tokenIds = [1, 2, 3];
      const hostessIndices = [0, 1, 2];
      const owners = [user1.address, user1.address, user2.address];

      await nftRewarder.connect(admin).batchRegisterNFTs(tokenIds, hostessIndices, owners);

      expect(await nftRewarder.totalRegisteredNFTs()).to.equal(3);
    });

    it("Should reject mismatched array lengths", async function () {
      await expect(
        nftRewarder.connect(admin).batchRegisterNFTs([1, 2], [0], [user1.address, user1.address])
      ).to.be.revertedWithCustomError(nftRewarder, "LengthMismatch");
    });
  });

  describe("Ownership Management", function () {
    beforeEach(async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address);
      await nftRewarder.connect(admin).registerNFT(2, 1, user1.address);
    });

    it("Should update ownership", async function () {
      await nftRewarder.connect(admin).updateOwnership(1, user2.address);

      const metadata = await nftRewarder.getNFTMetadata(1);
      expect(metadata._owner).to.equal(user2.address);
    });

    it("Should maintain ownerTokenIds arrays", async function () {
      let user1Tokens = await nftRewarder.getOwnerTokenIds(user1.address);
      expect(user1Tokens.length).to.equal(2);

      await nftRewarder.connect(admin).updateOwnership(1, user2.address);

      user1Tokens = await nftRewarder.getOwnerTokenIds(user1.address);
      let user2Tokens = await nftRewarder.getOwnerTokenIds(user2.address);

      expect(user1Tokens.length).to.equal(1);
      expect(user2Tokens.length).to.equal(1);
      expect(user2Tokens[0]).to.equal(1n);
    });

    it("Should emit OwnershipUpdated event", async function () {
      await expect(nftRewarder.connect(admin).updateOwnership(1, user2.address))
        .to.emit(nftRewarder, "OwnershipUpdated")
        .withArgs(1, user1.address, user2.address);
    });

    it("Should reject unregistered NFT ownership update", async function () {
      await expect(
        nftRewarder.connect(admin).updateOwnership(999, user2.address)
      ).to.be.revertedWithCustomError(nftRewarder, "NFTNotRegistered");
    });
  });

  describe("Reward Distribution", function () {
    beforeEach(async function () {
      // Register 3 NFTs with different multipliers
      // user1: Penelope (100), Mia (90) = 190 total
      // user2: Vivienne (30) = 30 total
      // Total: 220 multiplier points
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address); // Penelope 100
      await nftRewarder.connect(admin).registerNFT(2, 1, user1.address); // Mia 90
      await nftRewarder.connect(admin).registerNFT(3, 7, user2.address); // Vivienne 30
    });

    it("Should accept rewards from rogueBankroll", async function () {
      const betId = ethers.keccak256(ethers.toUtf8Bytes("test-bet-1"));
      const amount = ethers.parseEther("1.0");

      await expect(
        nftRewarder.connect(rogueBankroll).receiveReward(betId, { value: amount })
      ).to.emit(nftRewarder, "RewardReceived");

      expect(await nftRewarder.totalRewardsReceived()).to.equal(amount);
    });

    it("Should reject rewards from non-rogueBankroll", async function () {
      const betId = ethers.keccak256(ethers.toUtf8Bytes("test-bet-1"));

      await expect(
        nftRewarder.connect(user1).receiveReward(betId, { value: ethers.parseEther("1.0") })
      ).to.be.revertedWithCustomError(nftRewarder, "NotRogueBankroll");
    });

    it("Should reject zero reward amount", async function () {
      const betId = ethers.keccak256(ethers.toUtf8Bytes("test-bet-1"));

      await expect(
        nftRewarder.connect(rogueBankroll).receiveReward(betId, { value: 0 })
      ).to.be.revertedWithCustomError(nftRewarder, "NoRewardsToClaim");
    });

    it("Should calculate pending rewards proportionally", async function () {
      const betId = ethers.keccak256(ethers.toUtf8Bytes("test-bet-1"));
      const amount = ethers.parseEther("2.2"); // 2.2 ETH, divisible by 220

      await nftRewarder.connect(rogueBankroll).receiveReward(betId, { value: amount });

      // Expected rewards:
      // NFT 1 (100 points): 100/220 * 2.2 = 1.0 ETH
      // NFT 2 (90 points): 90/220 * 2.2 = 0.9 ETH
      // NFT 3 (30 points): 30/220 * 2.2 = 0.3 ETH

      const pending1 = await nftRewarder.pendingReward(1);
      const pending2 = await nftRewarder.pendingReward(2);
      const pending3 = await nftRewarder.pendingReward(3);

      // Allow small rounding differences
      expect(pending1).to.be.closeTo(ethers.parseEther("1.0"), ethers.parseEther("0.001"));
      expect(pending2).to.be.closeTo(ethers.parseEther("0.9"), ethers.parseEther("0.001"));
      expect(pending3).to.be.closeTo(ethers.parseEther("0.3"), ethers.parseEther("0.001"));
    });

    it("Should not give rewards to newly registered NFTs for past rewards", async function () {
      const betId = ethers.keccak256(ethers.toUtf8Bytes("test-bet-1"));
      await nftRewarder.connect(rogueBankroll).receiveReward(betId, { value: ethers.parseEther("1.0") });

      // Register new NFT after reward
      await nftRewarder.connect(admin).registerNFT(4, 0, user3.address);

      // New NFT should have 0 pending rewards
      expect(await nftRewarder.pendingReward(4)).to.equal(0);
    });
  });

  describe("Withdrawal", function () {
    beforeEach(async function () {
      // Register NFTs
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address); // 100
      await nftRewarder.connect(admin).registerNFT(2, 1, user1.address); // 90

      // Send rewards
      const betId = ethers.keccak256(ethers.toUtf8Bytes("test-bet-1"));
      await nftRewarder.connect(rogueBankroll).receiveReward(betId, { value: ethers.parseEther("1.9") });
    });

    it("Should withdraw rewards to recipient", async function () {
      const balanceBefore = await ethers.provider.getBalance(user1.address);

      await nftRewarder.connect(admin).withdrawTo([1, 2], user1.address);

      const balanceAfter = await ethers.provider.getBalance(user1.address);
      expect(balanceAfter - balanceBefore).to.be.closeTo(ethers.parseEther("1.9"), ethers.parseEther("0.001"));
    });

    it("Should update reward tracking after withdrawal", async function () {
      await nftRewarder.connect(admin).withdrawTo([1, 2], user1.address);

      expect(await nftRewarder.pendingReward(1)).to.equal(0);
      expect(await nftRewarder.pendingReward(2)).to.equal(0);
      expect(await nftRewarder.totalRewardsDistributed()).to.be.closeTo(
        ethers.parseEther("1.9"), ethers.parseEther("0.001")
      );
    });

    it("Should track user total claimed", async function () {
      await nftRewarder.connect(admin).withdrawTo([1, 2], user1.address);

      const claimed = await nftRewarder.userTotalClaimed(user1.address);
      expect(claimed).to.be.closeTo(ethers.parseEther("1.9"), ethers.parseEther("0.001"));
    });

    it("Should emit RewardClaimed event", async function () {
      await expect(nftRewarder.connect(admin).withdrawTo([1, 2], user1.address))
        .to.emit(nftRewarder, "RewardClaimed");
    });

    it("Should reject withdrawal with no rewards", async function () {
      // First withdrawal
      await nftRewarder.connect(admin).withdrawTo([1, 2], user1.address);

      // Second withdrawal should fail
      await expect(
        nftRewarder.connect(admin).withdrawTo([1, 2], user1.address)
      ).to.be.revertedWithCustomError(nftRewarder, "NoRewardsToClaim");
    });

    it("Should reject non-admin withdrawal", async function () {
      await expect(
        nftRewarder.connect(user1).withdrawTo([1, 2], user1.address)
      ).to.be.revertedWithCustomError(nftRewarder, "NotAdmin");
    });
  });

  describe("View Functions", function () {
    beforeEach(async function () {
      // Register NFTs
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address); // 100
      await nftRewarder.connect(admin).registerNFT(2, 1, user1.address); // 90
      await nftRewarder.connect(admin).registerNFT(3, 7, user2.address); // 30

      // Send rewards
      const betId = ethers.keccak256(ethers.toUtf8Bytes("test-bet-1"));
      await nftRewarder.connect(rogueBankroll).receiveReward(betId, { value: ethers.parseEther("2.2") });
    });

    it("getOwnerEarnings should return correct data", async function () {
      const [totalPending, totalClaimed, tokenIds] = await nftRewarder.getOwnerEarnings(user1.address);

      expect(tokenIds.length).to.equal(2);
      expect(totalClaimed).to.equal(0);
      // user1 has 190/220 of 2.2 ETH = 1.9 ETH
      expect(totalPending).to.be.closeTo(ethers.parseEther("1.9"), ethers.parseEther("0.001"));
    });

    it("getTokenEarnings should return correct data", async function () {
      const [pending, claimed, multipliers] = await nftRewarder.getTokenEarnings([1, 2, 3]);

      expect(pending[0]).to.be.closeTo(ethers.parseEther("1.0"), ethers.parseEther("0.001")); // 100/220 * 2.2
      expect(pending[1]).to.be.closeTo(ethers.parseEther("0.9"), ethers.parseEther("0.001")); // 90/220 * 2.2
      expect(pending[2]).to.be.closeTo(ethers.parseEther("0.3"), ethers.parseEther("0.001")); // 30/220 * 2.2
      expect(multipliers[0]).to.equal(100);
      expect(multipliers[1]).to.equal(90);
      expect(multipliers[2]).to.equal(30);
    });

    it("getNFTEarnings should return correct data", async function () {
      const [totalEarned, pendingAmount, hostessIndex] = await nftRewarder.getNFTEarnings(1);

      expect(totalEarned).to.be.closeTo(ethers.parseEther("1.0"), ethers.parseEther("0.001"));
      expect(pendingAmount).to.be.closeTo(ethers.parseEther("1.0"), ethers.parseEther("0.001"));
      expect(hostessIndex).to.equal(0);
    });

    it("getGlobalStats should return correct data", async function () {
      const [totalRewards, totalDistributed, totalPending, registeredNFTs, totalPoints] =
        await nftRewarder.getGlobalStats();

      expect(totalRewards).to.equal(ethers.parseEther("2.2"));
      expect(totalDistributed).to.equal(0);
      expect(totalPending).to.equal(ethers.parseEther("2.2"));
      expect(registeredNFTs).to.equal(3);
      expect(totalPoints).to.equal(220);
    });

    it("getMultiplier should return correct values", async function () {
      for (let i = 0; i < 8; i++) {
        expect(await nftRewarder.getMultiplier(i)).to.equal(MULTIPLIERS[i]);
      }
    });

    it("getMultiplier should revert for invalid index", async function () {
      await expect(nftRewarder.getMultiplier(8))
        .to.be.revertedWithCustomError(nftRewarder, "InvalidHostessIndex");
    });
  });

  describe("Multiple Reward Cycles", function () {
    beforeEach(async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address); // 100
      await nftRewarder.connect(admin).registerNFT(2, 0, user2.address); // 100
    });

    it("Should accumulate rewards over multiple cycles", async function () {
      // First reward
      const betId1 = ethers.keccak256(ethers.toUtf8Bytes("bet-1"));
      await nftRewarder.connect(rogueBankroll).receiveReward(betId1, { value: ethers.parseEther("1.0") });

      // Second reward
      const betId2 = ethers.keccak256(ethers.toUtf8Bytes("bet-2"));
      await nftRewarder.connect(rogueBankroll).receiveReward(betId2, { value: ethers.parseEther("1.0") });

      // Each NFT should have 1.0 ETH (0.5 + 0.5 from each cycle)
      expect(await nftRewarder.pendingReward(1)).to.be.closeTo(
        ethers.parseEther("1.0"), ethers.parseEther("0.001")
      );
    });

    it("Should handle partial withdrawals", async function () {
      const betId1 = ethers.keccak256(ethers.toUtf8Bytes("bet-1"));
      await nftRewarder.connect(rogueBankroll).receiveReward(betId1, { value: ethers.parseEther("2.0") });

      // User1 withdraws
      await nftRewarder.connect(admin).withdrawTo([1], user1.address);

      // More rewards come in
      const betId2 = ethers.keccak256(ethers.toUtf8Bytes("bet-2"));
      await nftRewarder.connect(rogueBankroll).receiveReward(betId2, { value: ethers.parseEther("2.0") });

      // User1 should have 1.0 ETH (just from second cycle)
      // User2 should have 2.0 ETH (1.0 from each cycle)
      expect(await nftRewarder.pendingReward(1)).to.be.closeTo(
        ethers.parseEther("1.0"), ethers.parseEther("0.001")
      );
      expect(await nftRewarder.pendingReward(2)).to.be.closeTo(
        ethers.parseEther("2.0"), ethers.parseEther("0.001")
      );
    });
  });

  describe("Edge Cases", function () {
    it("Should handle zero address owner registration", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, ethers.ZeroAddress);

      const metadata = await nftRewarder.getNFTMetadata(1);
      expect(metadata.registered).to.equal(true);
      expect(metadata._owner).to.equal(ethers.ZeroAddress);
    });

    it("Should receive direct ROGUE without updating rewards", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address);

      // Send ROGUE directly (not via receiveReward)
      await owner.sendTransaction({
        to: await nftRewarder.getAddress(),
        value: ethers.parseEther("1.0")
      });

      // totalRewardsReceived should not change
      expect(await nftRewarder.totalRewardsReceived()).to.equal(0);
      // But balance should increase
      expect(await ethers.provider.getBalance(await nftRewarder.getAddress())).to.equal(
        ethers.parseEther("1.0")
      );
    });

    it("Should fail receiveReward when no NFTs registered", async function () {
      const betId = ethers.keccak256(ethers.toUtf8Bytes("test-bet"));

      await expect(
        nftRewarder.connect(rogueBankroll).receiveReward(betId, { value: ethers.parseEther("1.0") })
      ).to.be.revertedWithCustomError(nftRewarder, "NoNFTsRegistered");
    });
  });

  // ============ V3: Time-Based Rewards Tests ============

  describe("V3 Initialization", function () {
    it("Should initialize V3 with correct time reward rates", async function () {
      await nftRewarder.initializeV3();

      // Check Penelope rate (100x baseline)
      const penelopeRate = await nftRewarder.timeRewardRatesPerSecond(0);
      expect(penelopeRate).to.equal(2_125_029_000_000_000_000n);

      // Check Vivienne rate (30x baseline)
      const vivienneRate = await nftRewarder.timeRewardRatesPerSecond(7);
      expect(vivienneRate).to.equal(637_438_000_000_000_000n);
    });

    it("Should emit TimeRewardRatesSet event", async function () {
      await expect(nftRewarder.initializeV3())
        .to.emit(nftRewarder, "TimeRewardRatesSet");
    });

    it("Should not allow reinitializing V3", async function () {
      await nftRewarder.initializeV3();
      await expect(nftRewarder.initializeV3())
        .to.be.revertedWithCustomError(nftRewarder, "InvalidInitialization");
    });
  });

  describe("Time Reward Pool Management", function () {
    beforeEach(async function () {
      await nftRewarder.initializeV3();
    });

    it("Should deposit time rewards", async function () {
      const depositAmount = ethers.parseEther("1000");
      await nftRewarder.depositTimeRewards({ value: depositAmount });

      expect(await nftRewarder.timeRewardPoolDeposited()).to.equal(depositAmount);
      expect(await nftRewarder.timeRewardPoolRemaining()).to.equal(depositAmount);
    });

    it("Should emit TimeRewardDeposited event", async function () {
      const depositAmount = ethers.parseEther("1000");
      await expect(nftRewarder.depositTimeRewards({ value: depositAmount }))
        .to.emit(nftRewarder, "TimeRewardDeposited")
        .withArgs(depositAmount);
    });

    it("Should reject zero deposit", async function () {
      await expect(nftRewarder.depositTimeRewards({ value: 0 }))
        .to.be.revertedWithCustomError(nftRewarder, "NoRewardsToClaim");
    });

    it("Should reject non-owner deposit", async function () {
      await expect(nftRewarder.connect(user1).depositTimeRewards({ value: ethers.parseEther("100") }))
        .to.be.revertedWithCustomError(nftRewarder, "OwnableUnauthorizedAccount");
    });

    it("Should withdraw unused pool", async function () {
      const depositAmount = ethers.parseEther("1000");
      await nftRewarder.depositTimeRewards({ value: depositAmount });

      const balanceBefore = await ethers.provider.getBalance(owner.address);
      const tx = await nftRewarder.withdrawUnusedTimeRewardPool();
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const balanceAfter = await ethers.provider.getBalance(owner.address);

      expect(balanceAfter - balanceBefore + gasUsed).to.equal(depositAmount);
      expect(await nftRewarder.timeRewardPoolRemaining()).to.equal(0);
    });

    it("Should reject withdrawal with empty pool", async function () {
      await expect(nftRewarder.withdrawUnusedTimeRewardPool())
        .to.be.revertedWithCustomError(nftRewarder, "NoRewardsToClaim");
    });
  });

  describe("Special NFT Registration (Auto-Start)", function () {
    beforeEach(async function () {
      await nftRewarder.initializeV3();
      await nftRewarder.depositTimeRewards({ value: ethers.parseEther("100") });
    });

    it("Should auto-start time rewards for special NFTs (2340-2700)", async function () {
      // Register a special NFT (token ID 2340)
      await nftRewarder.connect(admin).registerNFT(2340, 0, user1.address); // Penelope

      const info = await nftRewarder.getTimeRewardInfo(2340);
      // getTimeRewardInfo returns: startTime, endTime, pending, claimed, ratePerSecond, timeRemaining, totalFor180Days, isActive
      expect(info[0]).to.be.gt(0); // startTime
      expect(info[3]).to.equal(0); // claimed (totalClaimed)
      expect(info[4]).to.equal(2_125_029_000_000_000_000n); // ratePerSecond
      expect(info[7]).to.equal(true); // isActive
    });

    it("Should emit TimeRewardStarted event for special NFTs", async function () {
      await expect(nftRewarder.connect(admin).registerNFT(2340, 0, user1.address))
        .to.emit(nftRewarder, "TimeRewardStarted");
    });

    it("Should increment totalSpecialNFTsRegistered", async function () {
      await nftRewarder.connect(admin).registerNFT(2340, 0, user1.address);
      expect(await nftRewarder.totalSpecialNFTsRegistered()).to.equal(1);

      await nftRewarder.connect(admin).registerNFT(2341, 1, user1.address);
      expect(await nftRewarder.totalSpecialNFTsRegistered()).to.equal(2);
    });

    it("Should NOT auto-start time rewards for regular NFTs", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address); // Regular NFT

      const info = await nftRewarder.getTimeRewardInfo(1);
      // getTimeRewardInfo returns: startTime, endTime, pending, claimed, ratePerSecond, timeRemaining, totalFor180Days, isActive
      expect(info[0]).to.equal(0); // startTime
      expect(info[4]).to.equal(0); // ratePerSecond
      expect(info[7]).to.equal(false); // isActive
    });

    it("Should NOT increment totalSpecialNFTsRegistered for regular NFTs", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address);
      expect(await nftRewarder.totalSpecialNFTsRegistered()).to.equal(0);
    });
  });

  describe("Pending Time Rewards Calculation", function () {
    beforeEach(async function () {
      await nftRewarder.initializeV3();
      await nftRewarder.depositTimeRewards({ value: ethers.parseEther("1000") });
      await nftRewarder.connect(admin).registerNFT(2340, 0, user1.address); // Penelope
    });

    it("Should calculate pending rewards correctly after time passes", async function () {
      // Advance time by 1 day (86400 seconds)
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);

      const [pending, ratePerSecond, timeRemaining] = await nftRewarder.pendingTimeReward(2340);

      // Expected: 2.125029 * 86400 = 183,602.5056 ROGUE
      const expectedPending = 2_125_029_000_000_000_000n * 86400n / BigInt(1e18);
      expect(pending).to.be.closeTo(expectedPending, ethers.parseEther("1"));

      // Rate should be Penelope rate
      expect(ratePerSecond).to.equal(2_125_029_000_000_000_000n);

      // Time remaining should be ~179 days
      expect(timeRemaining).to.be.closeTo(180n * 86400n - 86400n, 10);
    });

    it("Should cap rewards at 180 days", async function () {
      // Advance time by 200 days
      await ethers.provider.send("evm_increaseTime", [200 * 86400]);
      await ethers.provider.send("evm_mine", []);

      const [pending, , timeRemaining] = await nftRewarder.pendingTimeReward(2340);

      // Expected max: 2.125029 * 180 * 86400 = 33,048,449.76 ROGUE
      const maxPending = 2_125_029_000_000_000_000n * 180n * 86400n / BigInt(1e18);
      expect(pending).to.be.closeTo(maxPending, ethers.parseEther("100"));

      // Time remaining should be 0
      expect(timeRemaining).to.equal(0);
    });

    it("Should return zero for unstarted time rewards", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address); // Regular NFT

      const [pending, ratePerSecond, timeRemaining] = await nftRewarder.pendingTimeReward(1);
      expect(pending).to.equal(0);
      expect(ratePerSecond).to.equal(0);
      expect(timeRemaining).to.equal(0);
    });
  });

  describe("Time Reward Claims", function () {
    beforeEach(async function () {
      await nftRewarder.initializeV3();
      await nftRewarder.depositTimeRewards({ value: ethers.parseEther("10") });
      await nftRewarder.connect(admin).registerNFT(2340, 0, user1.address);
    });

    it("Should claim time rewards successfully", async function () {
      // Advance time by 1 hour (3600 seconds) - small amount to avoid exceeding pool
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);

      const balanceBefore = await ethers.provider.getBalance(user1.address);
      await nftRewarder.connect(admin).claimTimeRewards([2340], user1.address);
      const balanceAfter = await ethers.provider.getBalance(user1.address);

      // Should receive approximately 1 hour of rewards
      const expectedReward = 2_125_029_000_000_000_000n * 3600n / BigInt(1e18);
      expect(balanceAfter - balanceBefore).to.be.closeTo(expectedReward, ethers.parseEther("0.1"));
    });

    it("Should emit TimeRewardClaimed event", async function () {
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);

      await expect(nftRewarder.connect(admin).claimTimeRewards([2340], user1.address))
        .to.emit(nftRewarder, "TimeRewardClaimed");
    });

    it("Should update tracking after claim", async function () {
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);

      const [pendingBefore] = await nftRewarder.pendingTimeReward(2340);
      await nftRewarder.connect(admin).claimTimeRewards([2340], user1.address);
      const [pendingAfter] = await nftRewarder.pendingTimeReward(2340);

      expect(pendingAfter).to.equal(0);

      const info = await nftRewarder.getTimeRewardInfo(2340);
      // getTimeRewardInfo returns: startTime, endTime, pending, claimed, ratePerSecond, timeRemaining, totalFor180Days, isActive
      expect(info[3]).to.be.closeTo(pendingBefore, ethers.parseEther("0.1")); // claimed (totalClaimed)
    });

    it("Should reduce pool remaining after claim", async function () {
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);

      const poolBefore = await nftRewarder.timeRewardPoolRemaining();
      await nftRewarder.connect(admin).claimTimeRewards([2340], user1.address);
      const poolAfter = await nftRewarder.timeRewardPoolRemaining();

      expect(poolAfter).to.be.lt(poolBefore);
    });

    it("Should reject claim with insufficient pool", async function () {
      // Withdraw the entire pool first
      await nftRewarder.withdrawUnusedTimeRewardPool();

      // Deposit a tiny amount
      await nftRewarder.depositTimeRewards({ value: 1n }); // Just 1 wei

      // Advance time to accumulate rewards
      await ethers.provider.send("evm_increaseTime", [60]); // 1 minute
      await ethers.provider.send("evm_mine", []);

      // Even 1 minute at 2.125 rate = ~127.5 wei, but pool only has 1 wei
      // Pending will be > pool remaining, should fail
      await expect(nftRewarder.connect(admin).claimTimeRewards([2340], user1.address))
        .to.be.revertedWithCustomError(nftRewarder, "InsufficientTimeRewardPool");
    });

    it("Should reject claim for unstarted time reward with NoRewardsToClaim", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address); // Regular NFT

      // Since time reward isn't started, pending is 0, which triggers NoRewardsToClaim
      await expect(nftRewarder.connect(admin).claimTimeRewards([1], user1.address))
        .to.be.revertedWithCustomError(nftRewarder, "NoRewardsToClaim");
    });
  });

  describe("WithdrawAll (Combined Revenue + Time Rewards)", function () {
    beforeEach(async function () {
      await nftRewarder.initializeV3();
      await nftRewarder.depositTimeRewards({ value: ethers.parseEther("10") });
      await nftRewarder.connect(admin).registerNFT(2340, 0, user1.address);

      // Send revenue rewards
      const betId = ethers.keccak256(ethers.toUtf8Bytes("test-bet"));
      await nftRewarder.connect(rogueBankroll).receiveReward(betId, { value: ethers.parseEther("1") });

      // Advance time for time rewards (1 hour)
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);
    });

    it("Should withdraw both revenue and time rewards", async function () {
      const balanceBefore = await ethers.provider.getBalance(user1.address);
      await nftRewarder.connect(admin).withdrawAll([2340], user1.address);
      const balanceAfter = await ethers.provider.getBalance(user1.address);

      // Should receive revenue + time rewards
      const receivedAmount = balanceAfter - balanceBefore;
      expect(receivedAmount).to.be.gt(ethers.parseEther("1")); // More than just revenue
    });

    it("Should work with only revenue rewards (no time rewards started)", async function () {
      await nftRewarder.connect(admin).registerNFT(1, 0, user2.address); // Regular NFT
      const betId2 = ethers.keccak256(ethers.toUtf8Bytes("test-bet-2"));
      await nftRewarder.connect(rogueBankroll).receiveReward(betId2, { value: ethers.parseEther("1") });

      const balanceBefore = await ethers.provider.getBalance(user2.address);
      await nftRewarder.connect(admin).withdrawAll([1], user2.address);
      const balanceAfter = await ethers.provider.getBalance(user2.address);

      expect(balanceAfter - balanceBefore).to.be.gt(0);
    });
  });

  describe("Manual Time Reward Start", function () {
    beforeEach(async function () {
      await nftRewarder.initializeV3();
      await nftRewarder.depositTimeRewards({ value: ethers.parseEther("100") });
      // Register as regular NFT first (simulating pre-registered NFT)
      await nftRewarder.connect(admin).registerNFT(2340, 0, user1.address);
    });

    it("Should verify isSpecialNFT function works correctly", async function () {
      // isSpecialNFT returns (isSpecial, hasStarted)
      const result2340 = await nftRewarder.isSpecialNFT(2340);
      expect(result2340[0]).to.equal(true);  // isSpecial
      expect(result2340[1]).to.equal(true);  // hasStarted (auto-started on register)

      // Register a regular NFT for comparison
      await nftRewarder.connect(admin).registerNFT(1, 0, user1.address);
      const result1 = await nftRewarder.isSpecialNFT(1);
      expect(result1[0]).to.equal(false);  // isSpecial
      expect(result1[1]).to.equal(false);  // hasStarted

      // Test boundary conditions
      const result2339 = await nftRewarder.isSpecialNFT(2339);
      expect(result2339[0]).to.equal(false);  // isSpecial (below range)

      const result2700 = await nftRewarder.isSpecialNFT(2700);
      expect(result2700[0]).to.equal(true);  // isSpecial (at upper bound)

      const result2701 = await nftRewarder.isSpecialNFT(2701);
      expect(result2701[0]).to.equal(false);  // isSpecial (above range)
    });
  });

  describe("View Functions (V3)", function () {
    beforeEach(async function () {
      await nftRewarder.initializeV3();
      await nftRewarder.depositTimeRewards({ value: ethers.parseEther("10") });
      await nftRewarder.connect(admin).registerNFT(2340, 0, user1.address);
      await nftRewarder.connect(admin).registerNFT(2341, 1, user1.address);

      // Send revenue rewards
      const betId = ethers.keccak256(ethers.toUtf8Bytes("test-bet"));
      await nftRewarder.connect(rogueBankroll).receiveReward(betId, { value: ethers.parseEther("1") });

      // Advance time (1 hour)
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);
    });

    it("getEarningsBreakdown should return time reward info", async function () {
      const breakdown = await nftRewarder.getEarningsBreakdown(2340);
      // Returns: pendingNow, alreadyClaimed, totalEarnedSoFar, futureEarnings, totalAllocation, ratePerSecond, percentComplete, secondsRemaining

      expect(breakdown[0]).to.be.gt(0); // pendingNow - 1 hour of time rewards
      expect(breakdown[1]).to.equal(0); // alreadyClaimed - nothing claimed yet
      expect(breakdown[2]).to.be.gt(0); // totalEarnedSoFar
      expect(breakdown[3]).to.be.gt(0); // futureEarnings - still have time left
      expect(breakdown[4]).to.be.gt(0); // totalAllocation (180 days worth)
      expect(breakdown[5]).to.equal(2_125_029_000_000_000_000n); // ratePerSecond (Penelope rate)
      expect(breakdown[7]).to.be.gt(0); // secondsRemaining
    });

    it("getOwnerTimeRewardStats should aggregate correctly", async function () {
      const stats = await nftRewarder.getOwnerTimeRewardStats(user1.address);
      // Returns: totalPending, totalClaimed, specialNFTCount

      expect(stats[0]).to.be.gt(0); // totalPendingTimeRewards
      expect(stats[1]).to.equal(0); // totalTimeRewardsClaimed
      expect(stats[2]).to.equal(2); // specialNFTCount
    });

    it("getTimeRewardPoolStats should return correct data", async function () {
      const stats = await nftRewarder.getTimeRewardPoolStats();
      // Returns: poolDeposited, poolRemaining, poolClaimed, specialNFTsRegistered

      expect(stats[0]).to.equal(ethers.parseEther("10")); // poolDeposited
      expect(stats[1]).to.equal(ethers.parseEther("10")); // poolRemaining
      expect(stats[2]).to.equal(0); // poolClaimed
      expect(stats[3]).to.equal(2); // specialNFTsRegistered
    });
  });
});

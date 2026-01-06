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
      [rogueBankroll.address, admin.address],
      { initializer: "initialize" }
    );
    await nftRewarder.waitForDeployment();
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
      const NFTRewarder2 = await ethers.getContractFactory("NFTRewarder");
      await expect(
        upgrades.deployProxy(
          NFTRewarder2,
          [rogueBankroll.address, ethers.ZeroAddress],
          { initializer: "initialize" }
        )
      ).to.be.revertedWithCustomError(NFTRewarder2, "InvalidAddress");
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
});

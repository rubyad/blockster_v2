const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("AirdropVault", function () {
  let AirdropVault;
  let vault;
  let mockBux;
  let owner;
  let user1;
  let user2;
  let user3;
  let external1;
  let external2;
  let external3;

  // Provably fair helpers
  const SERVER_SEED = ethers.encodeBytes32String("test-server-seed-123");
  const COMMITMENT_HASH = ethers.sha256(ethers.solidityPacked(["bytes32"], [SERVER_SEED]));

  async function deployFresh() {
    [owner, user1, user2, user3, external1, external2, external3] = await ethers.getSigners();

    // Deploy mock BUX token
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockBux = await MockToken.deploy("Mock BUX", "BUX", 18);
    await mockBux.waitForDeployment();

    // Deploy AirdropVault as UUPS proxy
    AirdropVault = await ethers.getContractFactory("AirdropVault");
    vault = await upgrades.deployProxy(
      AirdropVault,
      [await mockBux.getAddress()],
      { initializer: "initialize" }
    );
    await vault.waitForDeployment();

    // Mint BUX to users
    await mockBux.mint(user1.address, ethers.parseEther("10000"));
    await mockBux.mint(user2.address, ethers.parseEther("10000"));
    await mockBux.mint(user3.address, ethers.parseEther("10000"));

    // Users approve vault to spend their BUX
    const vaultAddress = await vault.getAddress();
    await mockBux.connect(user1).approve(vaultAddress, ethers.MaxUint256);
    await mockBux.connect(user2).approve(vaultAddress, ethers.MaxUint256);
    await mockBux.connect(user3).approve(vaultAddress, ethers.MaxUint256);
  }

  // Helper: start a round with default params
  async function startDefaultRound() {
    const endTime = (await ethers.provider.getBlock("latest")).timestamp + 86400;
    await vault.startRound(COMMITMENT_HASH, endTime);
    return endTime;
  }

  // Helper: deposit BUX for a user
  async function depositFor(blocksterWallet, externalWallet, amount) {
    await vault.depositFor(blocksterWallet, externalWallet, ethers.parseEther(amount.toString()));
  }

  // Helper: run full lifecycle (start → deposit → close → draw)
  async function fullLifecycle(depositors) {
    await startDefaultRound();
    for (const { bWallet, eWallet, amount } of depositors) {
      await depositFor(bWallet, eWallet, amount);
    }
    await vault.closeAirdrop();
    await vault.drawWinners(SERVER_SEED);
  }

  beforeEach(async function () {
    await deployFresh();
  });

  // ====================================================================
  // Deployment & Initialization
  // ====================================================================
  describe("Deployment & Initialization", function () {
    it("Should deploy as UUPS proxy with correct owner", async function () {
      expect(await vault.owner()).to.equal(owner.address);
    });

    it("Should store BUX token address correctly", async function () {
      expect(await vault.buxToken()).to.equal(await mockBux.getAddress());
    });

    it("Should start with roundId 0 (no rounds started)", async function () {
      expect(await vault.roundId()).to.equal(0);
    });

    it("Should start with isOpen false and isDrawn false", async function () {
      expect(await vault.isOpen()).to.equal(false);
      expect(await vault.isDrawn()).to.equal(false);
    });

    it("Should not allow double initialization", async function () {
      await expect(
        vault.initialize(await mockBux.getAddress())
      ).to.be.revertedWithCustomError(vault, "InvalidInitialization");
    });

    it("Should reject zero address for BUX token", async function () {
      const Factory = await ethers.getContractFactory("AirdropVault");
      await expect(
        upgrades.deployProxy(Factory, [ethers.ZeroAddress], { initializer: "initialize" })
      ).to.be.revertedWith("Invalid token address");
    });

    it("Should have NUM_WINNERS = 33", async function () {
      expect(await vault.NUM_WINNERS()).to.equal(33);
    });
  });

  // ====================================================================
  // UUPS Upgrade
  // ====================================================================
  describe("UUPS Upgrade", function () {
    it("Should upgrade to V2 and preserve state", async function () {
      // Start a round first to have state
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      const depositCount = await vault.getDepositCount();

      // Deploy V2 implementation directly (flattened OZ v5 only has upgradeToAndCall, not upgradeTo)
      const AirdropVaultV2 = await ethers.getContractFactory("AirdropVaultV2");
      const v2Impl = await AirdropVaultV2.deploy();
      await v2Impl.waitForDeployment();

      // Upgrade via upgradeToAndCall
      await vault.upgradeToAndCall(await v2Impl.getAddress(), "0x");

      // Attach V2 ABI to proxy
      const upgraded = AirdropVaultV2.attach(await vault.getAddress());

      // State preserved
      expect(await upgraded.owner()).to.equal(owner.address);
      expect(await upgraded.buxToken()).to.equal(await mockBux.getAddress());
      expect(await upgraded.roundId()).to.equal(1);
      expect(await upgraded.getDepositCount()).to.equal(depositCount);

      // V2 functionality works
      await upgraded.initializeV2();
      expect(await upgraded.newV2Variable()).to.equal(42);
      expect(await upgraded.version()).to.equal("v2");
    });

    it("Should reject upgrade from non-owner", async function () {
      const AirdropVaultV2 = await ethers.getContractFactory("AirdropVaultV2");
      const v2Impl = await AirdropVaultV2.deploy();
      await v2Impl.waitForDeployment();

      await expect(
        vault.connect(user1).upgradeToAndCall(await v2Impl.getAddress(), "0x")
      ).to.be.revertedWithCustomError(vault, "OwnableUnauthorizedAccount");
    });
  });

  // ====================================================================
  // Round Lifecycle
  // ====================================================================
  describe("Round Lifecycle", function () {
    it("Should start a round with correct state", async function () {
      const endTime = await startDefaultRound();

      expect(await vault.roundId()).to.equal(1);
      expect(await vault.isOpen()).to.equal(true);
      expect(await vault.isDrawn()).to.equal(false);
      expect(await vault.commitmentHash()).to.equal(COMMITMENT_HASH);
      expect(await vault.airdropEndTime()).to.equal(endTime);
      expect(await vault.totalEntries()).to.equal(0);
    });

    it("Should emit RoundStarted event", async function () {
      const endTime = (await ethers.provider.getBlock("latest")).timestamp + 86400;
      await expect(vault.startRound(COMMITMENT_HASH, endTime))
        .to.emit(vault, "RoundStarted")
        .withArgs(1, COMMITMENT_HASH, endTime);
    });

    it("Should reject startRound with zero commitment hash", async function () {
      const endTime = (await ethers.provider.getBlock("latest")).timestamp + 86400;
      await expect(
        vault.startRound(ethers.ZeroHash, endTime)
      ).to.be.revertedWith("Zero commitment hash");
    });

    it("Should reject startRound with past endTime", async function () {
      const pastTime = (await ethers.provider.getBlock("latest")).timestamp - 100;
      await expect(
        vault.startRound(COMMITMENT_HASH, pastTime)
      ).to.be.revertedWith("End time must be in future");
    });

    it("Should reject startRound while another round is open", async function () {
      await startDefaultRound();
      const endTime = (await ethers.provider.getBlock("latest")).timestamp + 86400;
      await expect(
        vault.startRound(COMMITMENT_HASH, endTime)
      ).to.be.revertedWith("Previous round still open");
    });

    it("Should allow startRound after previous round is closed", async function () {
      await startDefaultRound();
      await vault.closeAirdrop();
      // Need to draw or at least close the round
      // Can start new round after close (even without draw, the round is no longer open)
      const endTime = (await ethers.provider.getBlock("latest")).timestamp + 86400;
      await vault.startRound(COMMITMENT_HASH, endTime);
      expect(await vault.roundId()).to.equal(2);
    });

    it("Should reject startRound from non-owner", async function () {
      const endTime = (await ethers.provider.getBlock("latest")).timestamp + 86400;
      await expect(
        vault.connect(user1).startRound(COMMITMENT_HASH, endTime)
      ).to.be.revertedWithCustomError(vault, "OwnableUnauthorizedAccount");
    });

    it("Should close airdrop correctly", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);

      await vault.closeAirdrop();

      expect(await vault.isOpen()).to.equal(false);
      const blockHash = await vault.blockHashAtClose();
      expect(blockHash).to.not.equal(ethers.ZeroHash);
      expect(await vault.closeBlockNumber()).to.be.gt(0);
    });

    it("Should emit AirdropClosed event", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);

      await expect(vault.closeAirdrop()).to.emit(vault, "AirdropClosed");
    });

    it("Should reject close if round not open", async function () {
      await expect(vault.closeAirdrop()).to.be.revertedWith("Round not open");
    });

    it("Should reject double close", async function () {
      await startDefaultRound();
      await vault.closeAirdrop();
      await expect(vault.closeAirdrop()).to.be.revertedWith("Round not open");
    });

    it("Should reject close from non-owner", async function () {
      await startDefaultRound();
      await expect(
        vault.connect(user1).closeAirdrop()
      ).to.be.revertedWithCustomError(vault, "OwnableUnauthorizedAccount");
    });
  });

  // ====================================================================
  // Deposits
  // ====================================================================
  describe("Deposits", function () {
    beforeEach(async function () {
      await startDefaultRound();
    });

    it("Should record deposit with correct data", async function () {
      await depositFor(user1.address, external1.address, 100);

      const dep = await vault.getDeposit(0);
      expect(dep.blocksterWallet).to.equal(user1.address);
      expect(dep.externalWallet).to.equal(external1.address);
      expect(dep.amount).to.equal(ethers.parseEther("100"));
      expect(dep.startPosition).to.equal(1);
      expect(dep.endPosition).to.equal(ethers.parseEther("100"));
    });

    it("Should create sequential position blocks", async function () {
      await depositFor(user1.address, external1.address, 100);
      await depositFor(user2.address, external2.address, 200);

      const dep1 = await vault.getDeposit(0);
      const dep2 = await vault.getDeposit(1);

      expect(dep1.startPosition).to.equal(1);
      expect(dep1.endPosition).to.equal(ethers.parseEther("100"));
      expect(dep2.startPosition).to.equal(ethers.parseEther("100") + 1n);
      expect(dep2.endPosition).to.equal(ethers.parseEther("300"));
    });

    it("Should handle multiple deposits from same wallet", async function () {
      await depositFor(user1.address, external1.address, 50);
      await depositFor(user1.address, external1.address, 30);

      expect(await vault.getDepositCount()).to.equal(2);
      expect(await vault.totalDeposited(user1.address)).to.equal(ethers.parseEther("80"));
    });

    it("Should transfer BUX from blocksterWallet to vault", async function () {
      const balanceBefore = await mockBux.balanceOf(user1.address);
      await depositFor(user1.address, external1.address, 100);
      const balanceAfter = await mockBux.balanceOf(user1.address);

      expect(balanceBefore - balanceAfter).to.equal(ethers.parseEther("100"));
      expect(await mockBux.balanceOf(await vault.getAddress())).to.equal(ethers.parseEther("100"));
    });

    it("Should allow deposit of 1 BUX (no minimum)", async function () {
      await depositFor(user1.address, external1.address, 1);

      const dep = await vault.getDeposit(0);
      expect(dep.amount).to.equal(ethers.parseEther("1"));
      expect(dep.startPosition).to.equal(1);
      expect(dep.endPosition).to.equal(ethers.parseEther("1"));
    });

    it("Should emit BuxDeposited event", async function () {
      await expect(
        vault.depositFor(user1.address, external1.address, ethers.parseEther("100"))
      )
        .to.emit(vault, "BuxDeposited")
        .withArgs(1, user1.address, external1.address, ethers.parseEther("100"), 1, ethers.parseEther("100"));
    });

    it("Should reject deposit when round is not open (no round started)", async function () {
      // Deploy fresh vault without starting a round
      const MockToken = await ethers.getContractFactory("MockERC20");
      const freshBux = await MockToken.deploy("BUX", "BUX", 18);
      const Factory = await ethers.getContractFactory("AirdropVault");
      const freshVault = await upgrades.deployProxy(Factory, [await freshBux.getAddress()], { initializer: "initialize" });

      await expect(
        freshVault.depositFor(user1.address, external1.address, ethers.parseEther("100"))
      ).to.be.revertedWith("Round not open");
    });

    it("Should reject deposit after round is closed", async function () {
      await vault.closeAirdrop();
      await expect(
        vault.depositFor(user1.address, external1.address, ethers.parseEther("100"))
      ).to.be.revertedWith("Round not open");
    });

    it("Should reject deposit of zero amount", async function () {
      await expect(
        vault.depositFor(user1.address, external1.address, 0)
      ).to.be.revertedWith("Zero amount");
    });

    it("Should reject deposit with zero blockster wallet", async function () {
      await expect(
        vault.depositFor(ethers.ZeroAddress, external1.address, ethers.parseEther("100"))
      ).to.be.revertedWith("Invalid blockster wallet");
    });

    it("Should reject deposit with zero external wallet", async function () {
      await expect(
        vault.depositFor(user1.address, ethers.ZeroAddress, ethers.parseEther("100"))
      ).to.be.revertedWith("Invalid external wallet");
    });

    it("Should reject deposit from non-owner", async function () {
      await expect(
        vault.connect(user1).depositFor(user1.address, external1.address, ethers.parseEther("100"))
      ).to.be.revertedWithCustomError(vault, "OwnableUnauthorizedAccount");
    });

    it("Should update totalEntries correctly", async function () {
      await depositFor(user1.address, external1.address, 100);
      expect(await vault.totalEntries()).to.equal(ethers.parseEther("100"));

      await depositFor(user2.address, external2.address, 200);
      expect(await vault.totalEntries()).to.equal(ethers.parseEther("300"));
    });
  });

  // ====================================================================
  // Position Lookup (Binary Search)
  // ====================================================================
  describe("Position Lookup", function () {
    beforeEach(async function () {
      await startDefaultRound();
    });

    it("Should return correct wallet for first position", async function () {
      await depositFor(user1.address, external1.address, 100);
      const [bWallet, eWallet] = await vault.getWalletForPosition(1);
      expect(bWallet).to.equal(user1.address);
      expect(eWallet).to.equal(external1.address);
    });

    it("Should return correct wallet for last position in block", async function () {
      await depositFor(user1.address, external1.address, 100);
      const [bWallet] = await vault.getWalletForPosition(ethers.parseEther("100"));
      expect(bWallet).to.equal(user1.address);
    });

    it("Should return correct wallet for middle position", async function () {
      await depositFor(user1.address, external1.address, 100);
      const [bWallet] = await vault.getWalletForPosition(ethers.parseEther("50"));
      expect(bWallet).to.equal(user1.address);
    });

    it("Should find correct wallet with 2 deposits", async function () {
      await depositFor(user1.address, external1.address, 100);
      await depositFor(user2.address, external2.address, 200);

      // Position in first block
      const [bWallet1] = await vault.getWalletForPosition(1);
      expect(bWallet1).to.equal(user1.address);

      // Position in second block
      const [bWallet2] = await vault.getWalletForPosition(ethers.parseEther("100") + 1n);
      expect(bWallet2).to.equal(user2.address);

      // Last position
      const [bWallet3] = await vault.getWalletForPosition(ethers.parseEther("300"));
      expect(bWallet3).to.equal(user2.address);
    });

    it("Should work with many deposits (binary search efficiency)", async function () {
      // 20 deposits of 10 BUX each
      for (let i = 0; i < 20; i++) {
        const wallet = i % 2 === 0 ? user1 : user2;
        const extWallet = i % 2 === 0 ? external1 : external2;
        await depositFor(wallet.address, extWallet.address, 10);
      }

      // Check first, middle, and last positions
      const [first] = await vault.getWalletForPosition(1);
      expect(first).to.equal(user1.address);

      const midPos = ethers.parseEther("100");
      const [mid] = await vault.getWalletForPosition(midPos);
      expect(mid).to.equal(user2.address); // 10th deposit (0-indexed 9), user2

      const lastPos = ethers.parseEther("200");
      const [last] = await vault.getWalletForPosition(lastPos);
      expect(last).to.equal(user2.address); // 20th deposit (0-indexed 19), user2
    });

    it("Should revert for position 0", async function () {
      await depositFor(user1.address, external1.address, 100);
      await expect(vault.getWalletForPosition(0)).to.be.revertedWith("Position out of range");
    });

    it("Should revert for position > totalEntries", async function () {
      await depositFor(user1.address, external1.address, 100);
      await expect(
        vault.getWalletForPosition(ethers.parseEther("100") + 1n)
      ).to.be.revertedWith("Position out of range");
    });

    it("Should return all deposits for a user via getUserDeposits", async function () {
      await depositFor(user1.address, external1.address, 50);
      await depositFor(user2.address, external2.address, 30);
      await depositFor(user1.address, external1.address, 20);

      const user1Deps = await vault.getUserDeposits(user1.address);
      expect(user1Deps.length).to.equal(2);
      expect(user1Deps[0].amount).to.equal(ethers.parseEther("50"));
      expect(user1Deps[1].amount).to.equal(ethers.parseEther("20"));

      const user2Deps = await vault.getUserDeposits(user2.address);
      expect(user2Deps.length).to.equal(1);
    });
  });

  // ====================================================================
  // Winner Selection (drawWinners)
  // ====================================================================
  describe("Winner Selection", function () {
    it("Should revert if round not closed", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await expect(vault.drawWinners(SERVER_SEED)).to.be.revertedWith("Must close first");
    });

    it("Should revert if already drawn", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);
      await expect(vault.drawWinners(SERVER_SEED)).to.be.revertedWith("Already drawn");
    });

    it("Should revert if no entries", async function () {
      await startDefaultRound();
      await vault.closeAirdrop();
      await expect(vault.drawWinners(SERVER_SEED)).to.be.revertedWith("No entries");
    });

    it("Should revert with invalid server seed", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();

      const wrongSeed = ethers.encodeBytes32String("wrong-seed");
      await expect(vault.drawWinners(wrongSeed)).to.be.revertedWith("Invalid seed");
    });

    it("Should draw 33 winners successfully", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 1000);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      expect(await vault.isDrawn()).to.equal(true);
      expect(await vault.revealedServerSeed()).to.equal(SERVER_SEED);
    });

    it("Should emit 33 WinnerSelected events and 1 AirdropDrawn event", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 1000);
      await vault.closeAirdrop();

      const tx = await vault.drawWinners(SERVER_SEED);
      const receipt = await tx.wait();

      // Count WinnerSelected events
      const winnerEvents = receipt.logs.filter(log => {
        try {
          return vault.interface.parseLog(log)?.name === "WinnerSelected";
        } catch { return false; }
      });
      expect(winnerEvents.length).to.equal(33);

      // Count AirdropDrawn events
      const drawnEvents = receipt.logs.filter(log => {
        try {
          return vault.interface.parseLog(log)?.name === "AirdropDrawn";
        } catch { return false; }
      });
      expect(drawnEvents.length).to.equal(1);
    });

    it("Should produce random numbers between 1 and totalEntries", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 1000);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      const totalEntries = await vault.totalEntries();
      for (let i = 1; i <= 33; i++) {
        const info = await vault.getWinnerInfo(i);
        expect(info.randomNumber).to.be.gte(1);
        expect(info.randomNumber).to.be.lte(totalEntries);
      }
    });

    it("Should assign correct wallet data to each winner", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 500);
      await depositFor(user2.address, external2.address, 500);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      for (let i = 1; i <= 33; i++) {
        const info = await vault.getWinnerInfo(i);
        // Each winner must map to one of our depositors
        const isUser1 = info.blocksterWallet === user1.address;
        const isUser2 = info.blocksterWallet === user2.address;
        expect(isUser1 || isUser2).to.equal(true);

        if (isUser1) {
          expect(info.externalWallet).to.equal(external1.address);
        } else {
          expect(info.externalWallet).to.equal(external2.address);
        }
      }
    });

    it("Should be deterministic — same seed + same blockHash = same winners", async function () {
      // We can't control blockHash between tests, but we can verify that
      // the on-chain computation is deterministic by re-deriving off-chain
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 500);
      await depositFor(user2.address, external2.address, 500);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      const totalEntries = await vault.totalEntries();
      const blockHash = await vault.blockHashAtClose();

      // Re-derive winners off-chain
      const combinedSeed = ethers.keccak256(
        ethers.solidityPacked(["bytes32", "bytes32"], [SERVER_SEED, blockHash])
      );

      for (let i = 0; i < 33; i++) {
        const hash = ethers.keccak256(
          ethers.solidityPacked(["bytes32", "uint256"], [combinedSeed, i])
        );
        const expectedRandom = (BigInt(hash) % totalEntries) + 1n;

        const info = await vault.getWinnerInfo(i + 1);
        expect(info.randomNumber).to.equal(expectedRandom);
      }
    });

    it("Should allow same wallet to win multiple prizes", async function () {
      // Single depositor = all 33 prizes go to them
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      for (let i = 1; i <= 33; i++) {
        const info = await vault.getWinnerInfo(i);
        expect(info.blocksterWallet).to.equal(user1.address);
        expect(info.externalWallet).to.equal(external1.address);
      }
    });

    it("Should reject drawWinners from non-owner", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await expect(
        vault.connect(user1).drawWinners(SERVER_SEED)
      ).to.be.revertedWithCustomError(vault, "OwnableUnauthorizedAccount");
    });
  });

  // ====================================================================
  // getWinnerInfo View Function
  // ====================================================================
  describe("getWinnerInfo", function () {
    beforeEach(async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 500);
      await depositFor(user2.address, external2.address, 500);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);
    });

    it("Should return correct data for prizePosition 1 (1st place)", async function () {
      const info = await vault.getWinnerInfo(1);
      expect(info.blocksterWallet).to.not.equal(ethers.ZeroAddress);
      expect(info.externalWallet).to.not.equal(ethers.ZeroAddress);
      expect(info.buxRedeemed).to.be.gt(0);
      expect(info.blockStart).to.be.gte(1);
      expect(info.blockEnd).to.be.gt(info.blockStart);
      expect(info.randomNumber).to.be.gte(1);
    });

    it("Should return correct data for all 33 positions", async function () {
      for (let i = 1; i <= 33; i++) {
        const info = await vault.getWinnerInfo(i);
        // randomNumber falls within blockStart–blockEnd
        expect(info.randomNumber).to.be.gte(info.blockStart);
        expect(info.randomNumber).to.be.lte(info.blockEnd);
      }
    });

    it("Should revert for prizePosition 0", async function () {
      await expect(vault.getWinnerInfo(0)).to.be.revertedWith("Invalid prize position");
    });

    it("Should revert for prizePosition 34", async function () {
      await expect(vault.getWinnerInfo(34)).to.be.revertedWith("Invalid prize position");
    });

    it("Should revert before draw", async function () {
      // Deploy fresh and don't draw
      const MockToken = await ethers.getContractFactory("MockERC20");
      const freshBux = await MockToken.deploy("BUX", "BUX", 18);
      const Factory = await ethers.getContractFactory("AirdropVault");
      const freshVault = await upgrades.deployProxy(Factory, [await freshBux.getAddress()], { initializer: "initialize" });

      await expect(freshVault.getWinnerInfo(1)).to.be.revertedWith("Airdrop not drawn yet");
    });
  });

  // ====================================================================
  // verifyFairness
  // ====================================================================
  describe("verifyFairness", function () {
    it("Should return all four values correctly after draw", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      const [commitment, seed, blockHash, entries] = await vault.verifyFairness();
      expect(commitment).to.equal(COMMITMENT_HASH);
      expect(seed).to.equal(SERVER_SEED);
      expect(blockHash).to.not.equal(ethers.ZeroHash);
      expect(entries).to.equal(ethers.parseEther("100"));
    });

    it("Should verify SHA256(revealedServerSeed) == commitmentHash", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      const [commitment, seed] = await vault.verifyFairness();
      const computedHash = ethers.sha256(ethers.solidityPacked(["bytes32"], [seed]));
      expect(computedHash).to.equal(commitment);
    });

    it("Should return empty seed before draw", async function () {
      await startDefaultRound();
      const [commitment, seed] = await vault.verifyFairness();
      expect(commitment).to.equal(COMMITMENT_HASH);
      expect(seed).to.equal(ethers.ZeroHash);
    });
  });

  // ====================================================================
  // Multi-Round
  // ====================================================================
  describe("Multi-Round", function () {
    it("Should complete round 1 then start round 2", async function () {
      // Round 1
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      expect(await vault.roundId()).to.equal(1);

      // Round 2
      const seed2 = ethers.encodeBytes32String("round-2-seed");
      const commitment2 = ethers.sha256(ethers.solidityPacked(["bytes32"], [seed2]));
      const endTime2 = (await ethers.provider.getBlock("latest")).timestamp + 86400;
      await vault.startRound(commitment2, endTime2);

      expect(await vault.roundId()).to.equal(2);
      expect(await vault.isOpen()).to.equal(true);
      expect(await vault.isDrawn()).to.equal(false);
      expect(await vault.totalEntries()).to.equal(0);
      expect(await vault.commitmentHash()).to.equal(commitment2);
    });

    it("Should keep round 1 data accessible after round 2 starts", async function () {
      // Round 1
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      // Verify round 1 winner data
      const r1Winner = await vault.getWinnerInfoForRound(1, 1);
      expect(r1Winner.blocksterWallet).to.equal(user1.address);

      // Start round 2
      const seed2 = ethers.encodeBytes32String("round-2-seed");
      const commitment2 = ethers.sha256(ethers.solidityPacked(["bytes32"], [seed2]));
      const endTime2 = (await ethers.provider.getBlock("latest")).timestamp + 86400;
      await vault.startRound(commitment2, endTime2);

      // Round 1 data still accessible
      const r1WinnerAfter = await vault.getWinnerInfoForRound(1, 1);
      expect(r1WinnerAfter.blocksterWallet).to.equal(user1.address);
      expect(r1WinnerAfter.randomNumber).to.equal(r1Winner.randomNumber);
    });

    it("Should handle round 2 independently from round 1", async function () {
      // Round 1
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      // Round 2 with different depositor
      const seed2 = ethers.encodeBytes32String("round-2-seed");
      const commitment2 = ethers.sha256(ethers.solidityPacked(["bytes32"], [seed2]));
      const endTime2 = (await ethers.provider.getBlock("latest")).timestamp + 86400;
      await vault.startRound(commitment2, endTime2);

      await depositFor(user2.address, external2.address, 200);
      await vault.closeAirdrop();
      await vault.drawWinners(seed2);

      // Round 2 winners should be user2
      for (let i = 1; i <= 33; i++) {
        const info = await vault.getWinnerInfo(i);
        expect(info.blocksterWallet).to.equal(user2.address);
        expect(info.externalWallet).to.equal(external2.address);
      }

      // Round 1 winners should still be user1
      for (let i = 1; i <= 33; i++) {
        const info = await vault.getWinnerInfoForRound(1, i);
        expect(info.blocksterWallet).to.equal(user1.address);
        expect(info.externalWallet).to.equal(external1.address);
      }
    });

    it("Should track deposits per-round independently", async function () {
      // Round 1
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      expect(await vault.getDepositCountForRound(1)).to.equal(1);

      // Round 2
      const seed2 = ethers.encodeBytes32String("round-2-seed");
      const commitment2 = ethers.sha256(ethers.solidityPacked(["bytes32"], [seed2]));
      const endTime2 = (await ethers.provider.getBlock("latest")).timestamp + 86400;
      await vault.startRound(commitment2, endTime2);

      await depositFor(user2.address, external2.address, 50);
      await depositFor(user3.address, external3.address, 75);

      expect(await vault.getDepositCount()).to.equal(2);
      expect(await vault.getDepositCountForRound(1)).to.equal(1); // Unchanged
    });

    it("Should verify fairness for each round independently", async function () {
      // Round 1
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      const [c1, s1, bh1, e1] = await vault.verifyFairnessForRound(1);
      expect(c1).to.equal(COMMITMENT_HASH);
      expect(s1).to.equal(SERVER_SEED);
      expect(e1).to.equal(ethers.parseEther("100"));

      // Round 2
      const seed2 = ethers.encodeBytes32String("round-2-seed");
      const commitment2 = ethers.sha256(ethers.solidityPacked(["bytes32"], [seed2]));
      const endTime2 = (await ethers.provider.getBlock("latest")).timestamp + 86400;
      await vault.startRound(commitment2, endTime2);

      await depositFor(user2.address, external2.address, 200);
      await vault.closeAirdrop();
      await vault.drawWinners(seed2);

      const [c2, s2, bh2, e2] = await vault.verifyFairnessForRound(2);
      expect(c2).to.equal(commitment2);
      expect(s2).to.equal(seed2);
      expect(e2).to.equal(ethers.parseEther("200"));

      // Round 1 unchanged
      const [c1After] = await vault.verifyFairnessForRound(1);
      expect(c1After).to.equal(COMMITMENT_HASH);
    });
  });

  // ====================================================================
  // Edge Cases
  // ====================================================================
  describe("Edge Cases", function () {
    it("Should handle 1 depositor with 1 BUX — all 33 winners are same wallet", async function () {
      await startDefaultRound();

      // Deposit exactly 1 BUX (1e18 wei)
      await depositFor(user1.address, external1.address, 1);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      for (let i = 1; i <= 33; i++) {
        const info = await vault.getWinnerInfo(i);
        expect(info.blocksterWallet).to.equal(user1.address);
        expect(info.externalWallet).to.equal(external1.address);
        // With only 1 entry (1e18), all randoms mod 1e18 + 1 should be 1
        // Actually: random % totalEntries + 1, where totalEntries = 1e18
        // The random number will be between 1 and 1e18
        expect(info.randomNumber).to.be.gte(1);
        expect(info.randomNumber).to.be.lte(ethers.parseEther("1"));
      }
    });

    it("Should handle 2 depositors with equal amounts", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 500);
      await depositFor(user2.address, external2.address, 500);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      let user1Wins = 0;
      let user2Wins = 0;
      for (let i = 1; i <= 33; i++) {
        const info = await vault.getWinnerInfo(i);
        if (info.blocksterWallet === user1.address) user1Wins++;
        if (info.blocksterWallet === user2.address) user2Wins++;
      }

      // Both should win some prizes (with high probability)
      expect(user1Wins + user2Wins).to.equal(33);
      // With 50/50 split and 33 draws, extremely unlikely either gets 0
      expect(user1Wins).to.be.gte(1);
      expect(user2Wins).to.be.gte(1);
    });

    it("Should handle many deposits efficiently", async function () {
      await startDefaultRound();

      // 50 deposits alternating users
      for (let i = 0; i < 50; i++) {
        const user = i % 3 === 0 ? user1 : (i % 3 === 1 ? user2 : user3);
        const ext = i % 3 === 0 ? external1 : (i % 3 === 1 ? external2 : external3);
        await depositFor(user.address, ext.address, 10);
      }

      expect(await vault.getDepositCount()).to.equal(50);
      expect(await vault.totalEntries()).to.equal(ethers.parseEther("500"));

      // Close and draw should work
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      // All 33 winners should be valid
      for (let i = 1; i <= 33; i++) {
        const info = await vault.getWinnerInfo(i);
        expect(info.randomNumber).to.be.gte(info.blockStart);
        expect(info.randomNumber).to.be.lte(info.blockEnd);
      }
    });

    it("Should handle withdrawBux after draw", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      const vaultBalance = await mockBux.balanceOf(await vault.getAddress());
      expect(vaultBalance).to.equal(ethers.parseEther("100"));

      const ownerBalanceBefore = await mockBux.balanceOf(owner.address);
      await vault.withdrawBux(1);
      const ownerBalanceAfter = await mockBux.balanceOf(owner.address);

      expect(ownerBalanceAfter - ownerBalanceBefore).to.equal(ethers.parseEther("100"));
      expect(await mockBux.balanceOf(await vault.getAddress())).to.equal(0);
    });

    it("Should reject withdrawBux before draw", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();

      await expect(vault.withdrawBux(1)).to.be.revertedWith("Round not drawn yet");
    });

    it("Should reject withdrawBux with invalid roundId", async function () {
      await expect(vault.withdrawBux(0)).to.be.revertedWith("Invalid round");
      await expect(vault.withdrawBux(99)).to.be.revertedWith("Invalid round");
    });

    it("Should reject withdrawBux from non-owner", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      await expect(
        vault.connect(user1).withdrawBux(1)
      ).to.be.revertedWithCustomError(vault, "OwnableUnauthorizedAccount");
    });

    it("Should emit BuxWithdrawn event", async function () {
      await startDefaultRound();
      await depositFor(user1.address, external1.address, 100);
      await vault.closeAirdrop();
      await vault.drawWinners(SERVER_SEED);

      await expect(vault.withdrawBux(1))
        .to.emit(vault, "BuxWithdrawn")
        .withArgs(1, ethers.parseEther("100"));
    });

    it("Should expose getRoundState view function", async function () {
      await startDefaultRound();
      const state = await vault.getRoundState(1);
      expect(state.commitment).to.equal(COMMITMENT_HASH);
      expect(state.open).to.equal(true);
      expect(state.drawn).to.equal(false);
    });

    it("Should handle getDeposit with out-of-bounds index", async function () {
      await startDefaultRound();
      await expect(vault.getDeposit(0)).to.be.revertedWith("Index out of bounds");
    });
  });

  // ====================================================================
  // Full End-to-End Flow
  // ====================================================================
  describe("Full E2E Flow", function () {
    it("Should complete full lifecycle: start → deposit → close → draw → verify", async function () {
      // 1. Start round
      const endTime = await startDefaultRound();
      expect(await vault.roundId()).to.equal(1);

      // 2. Multiple deposits
      await depositFor(user1.address, external1.address, 500);
      await depositFor(user2.address, external2.address, 300);
      await depositFor(user3.address, external3.address, 200);

      expect(await vault.totalEntries()).to.equal(ethers.parseEther("1000"));
      expect(await vault.getDepositCount()).to.equal(3);

      // 3. Close airdrop
      await vault.closeAirdrop();
      expect(await vault.isOpen()).to.equal(false);

      // 4. Draw winners
      await vault.drawWinners(SERVER_SEED);
      expect(await vault.isDrawn()).to.equal(true);

      // 5. Verify all 33 winners
      for (let i = 1; i <= 33; i++) {
        const info = await vault.getWinnerInfo(i);

        // Winner must be one of our depositors
        const validWallet = [user1.address, user2.address, user3.address].includes(info.blocksterWallet);
        expect(validWallet).to.equal(true);

        // Random number must fall within deposit block
        expect(info.randomNumber).to.be.gte(info.blockStart);
        expect(info.randomNumber).to.be.lte(info.blockEnd);
      }

      // 6. Verify fairness
      const [commitment, seed, blockHash, entries] = await vault.verifyFairness();
      const computedHash = ethers.sha256(ethers.solidityPacked(["bytes32"], [seed]));
      expect(computedHash).to.equal(commitment);
      expect(entries).to.equal(ethers.parseEther("1000"));

      // 7. Withdraw BUX
      await vault.withdrawBux(1);
      expect(await mockBux.balanceOf(await vault.getAddress())).to.equal(0);
    });
  });
});

const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("AirdropPrizePool", function () {
  let AirdropPrizePool;
  let pool;
  let mockUsdt;
  let owner;
  let winner1;
  let winner2;
  let winner3;
  let nonOwner;

  // USDT has 6 decimals
  const USDT_DECIMALS = 6;
  const usdtAmount = (usd) => BigInt(usd) * 10n ** BigInt(USDT_DECIMALS);

  // Prize structure from plan
  const PRIZE_1ST = usdtAmount(250);
  const PRIZE_2ND = usdtAmount(150);
  const PRIZE_3RD = usdtAmount(100);
  const PRIZE_REST = usdtAmount(50);
  const TOTAL_PRIZES = usdtAmount(2000);

  async function deployFresh() {
    [owner, winner1, winner2, winner3, nonOwner] = await ethers.getSigners();

    // Deploy mock USDT (6 decimals)
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockUsdt = await MockToken.deploy("Mock USDT", "USDT", 6);
    await mockUsdt.waitForDeployment();

    // Deploy AirdropPrizePool as UUPS proxy
    AirdropPrizePool = await ethers.getContractFactory("AirdropPrizePool");
    pool = await upgrades.deployProxy(
      AirdropPrizePool,
      [await mockUsdt.getAddress()],
      { initializer: "initialize" }
    );
    await pool.waitForDeployment();

    // Mint USDT to owner for funding
    await mockUsdt.mint(owner.address, usdtAmount(100000));
    await mockUsdt.connect(owner).approve(await pool.getAddress(), ethers.MaxUint256);
  }

  beforeEach(async function () {
    await deployFresh();
  });

  // ====================================================================
  // Deployment & Initialization
  // ====================================================================
  describe("Deployment & Initialization", function () {
    it("Should deploy as UUPS proxy with correct owner", async function () {
      expect(await pool.owner()).to.equal(owner.address);
    });

    it("Should store USDT token address correctly", async function () {
      expect(await pool.usdt()).to.equal(await mockUsdt.getAddress());
    });

    it("Should start with roundId 1", async function () {
      expect(await pool.roundId()).to.equal(1);
    });

    it("Should not allow double initialization", async function () {
      await expect(
        pool.initialize(await mockUsdt.getAddress())
      ).to.be.revertedWithCustomError(pool, "InvalidInitialization");
    });

    it("Should reject zero address for USDT", async function () {
      const Factory = await ethers.getContractFactory("AirdropPrizePool");
      await expect(
        upgrades.deployProxy(Factory, [ethers.ZeroAddress], { initializer: "initialize" })
      ).to.be.revertedWith("Invalid USDT address");
    });

    it("Should have NUM_WINNERS = 33", async function () {
      expect(await pool.NUM_WINNERS()).to.equal(33);
    });
  });

  // ====================================================================
  // UUPS Upgrade
  // ====================================================================
  describe("UUPS Upgrade", function () {
    it("Should upgrade to V2 and preserve state", async function () {
      // Fund pool first to have state
      await pool.fundPrizePool(usdtAmount(1000));

      // Deploy V2 implementation directly (flattened OZ v5: upgradeToAndCall only)
      const AirdropPrizePoolV2 = await ethers.getContractFactory("AirdropPrizePoolV2");
      const v2Impl = await AirdropPrizePoolV2.deploy();
      await v2Impl.waitForDeployment();

      // Upgrade
      await pool.upgradeToAndCall(await v2Impl.getAddress(), "0x");

      // Attach V2 ABI
      const upgraded = AirdropPrizePoolV2.attach(await pool.getAddress());

      // State preserved
      expect(await upgraded.owner()).to.equal(owner.address);
      expect(await upgraded.usdt()).to.equal(await mockUsdt.getAddress());
      expect(await upgraded.roundId()).to.equal(1);
      expect(await upgraded.getPoolBalance()).to.equal(usdtAmount(1000));

      // V2 works
      await upgraded.initializeV2();
      expect(await upgraded.newV2Variable()).to.equal(99);
      expect(await upgraded.version()).to.equal("v2");
    });

    it("Should reject upgrade from non-owner", async function () {
      const AirdropPrizePoolV2 = await ethers.getContractFactory("AirdropPrizePoolV2");
      const v2Impl = await AirdropPrizePoolV2.deploy();
      await v2Impl.waitForDeployment();

      await expect(
        pool.connect(nonOwner).upgradeToAndCall(await v2Impl.getAddress(), "0x")
      ).to.be.revertedWithCustomError(pool, "OwnableUnauthorizedAccount");
    });
  });

  // ====================================================================
  // Funding
  // ====================================================================
  describe("Funding", function () {
    it("Should transfer USDT from owner to contract", async function () {
      const ownerBefore = await mockUsdt.balanceOf(owner.address);
      await pool.fundPrizePool(usdtAmount(2000));

      expect(await pool.getPoolBalance()).to.equal(usdtAmount(2000));
      expect(await mockUsdt.balanceOf(owner.address)).to.equal(ownerBefore - usdtAmount(2000));
    });

    it("Should emit PrizePoolFunded event", async function () {
      await expect(pool.fundPrizePool(usdtAmount(2000)))
        .to.emit(pool, "PrizePoolFunded")
        .withArgs(1, usdtAmount(2000));
    });

    it("Should allow multiple fundings", async function () {
      await pool.fundPrizePool(usdtAmount(1000));
      await pool.fundPrizePool(usdtAmount(500));
      expect(await pool.getPoolBalance()).to.equal(usdtAmount(1500));
    });

    it("Should reject zero amount", async function () {
      await expect(pool.fundPrizePool(0)).to.be.revertedWith("Zero amount");
    });

    it("Should reject funding from non-owner", async function () {
      await expect(
        pool.connect(nonOwner).fundPrizePool(usdtAmount(100))
      ).to.be.revertedWithCustomError(pool, "OwnableUnauthorizedAccount");
    });
  });

  // ====================================================================
  // Prize Configuration
  // ====================================================================
  describe("Prize Configuration", function () {
    it("Should store winner address and amount correctly", async function () {
      await pool.setPrize(1, 0, winner1.address, PRIZE_1ST);

      const prize = await pool.getPrize(1, 0);
      expect(prize.winner).to.equal(winner1.address);
      expect(prize.amount).to.equal(PRIZE_1ST);
      expect(prize.claimed).to.equal(false);
    });

    it("Should set all 33 prizes correctly", async function () {
      const winners = [winner1, winner2, winner3];

      // Set prizes: 1st=$250, 2nd=$150, 3rd=$100, 4th-33rd=$50
      await pool.setPrize(1, 0, winner1.address, PRIZE_1ST);
      await pool.setPrize(1, 1, winner2.address, PRIZE_2ND);
      await pool.setPrize(1, 2, winner3.address, PRIZE_3RD);
      for (let i = 3; i < 33; i++) {
        await pool.setPrize(1, i, winners[i % 3].address, PRIZE_REST);
      }

      // Verify all stored
      const prize0 = await pool.getPrize(1, 0);
      expect(prize0.amount).to.equal(PRIZE_1ST);

      const prize1 = await pool.getPrize(1, 1);
      expect(prize1.amount).to.equal(PRIZE_2ND);

      const prize32 = await pool.getPrize(1, 32);
      expect(prize32.amount).to.equal(PRIZE_REST);

      // Verify total
      expect(await pool.getRoundPrizeTotal(1)).to.equal(TOTAL_PRIZES);
    });

    it("Should reject winnerIndex >= 33", async function () {
      await expect(
        pool.setPrize(1, 33, winner1.address, PRIZE_REST)
      ).to.be.revertedWith("Invalid winner index");
    });

    it("Should reject zero address winner", async function () {
      await expect(
        pool.setPrize(1, 0, ethers.ZeroAddress, PRIZE_1ST)
      ).to.be.revertedWith("Invalid winner address");
    });

    it("Should reject zero prize amount", async function () {
      await expect(
        pool.setPrize(1, 0, winner1.address, 0)
      ).to.be.revertedWith("Zero prize amount");
    });

    it("Should emit PrizeSet event", async function () {
      await expect(pool.setPrize(1, 0, winner1.address, PRIZE_1ST))
        .to.emit(pool, "PrizeSet")
        .withArgs(1, 0, winner1.address, PRIZE_1ST);
    });

    it("Should reject setPrize from non-owner", async function () {
      await expect(
        pool.connect(nonOwner).setPrize(1, 0, winner1.address, PRIZE_1ST)
      ).to.be.revertedWithCustomError(pool, "OwnableUnauthorizedAccount");
    });

    it("Should allow overwriting a prize before it's claimed", async function () {
      await pool.setPrize(1, 0, winner1.address, PRIZE_1ST);
      await pool.setPrize(1, 0, winner2.address, PRIZE_2ND);

      const prize = await pool.getPrize(1, 0);
      expect(prize.winner).to.equal(winner2.address);
      expect(prize.amount).to.equal(PRIZE_2ND);
    });
  });

  // ====================================================================
  // Prize Distribution
  // ====================================================================
  describe("Prize Distribution", function () {
    beforeEach(async function () {
      // Fund and set a prize
      await pool.fundPrizePool(usdtAmount(5000));
      await pool.setPrize(1, 0, winner1.address, PRIZE_1ST);
      await pool.setPrize(1, 1, winner2.address, PRIZE_2ND);
    });

    it("Should transfer correct USDT amount to winner", async function () {
      const balanceBefore = await mockUsdt.balanceOf(winner1.address);
      await pool.sendPrize(1, 0);
      const balanceAfter = await mockUsdt.balanceOf(winner1.address);

      expect(balanceAfter - balanceBefore).to.equal(PRIZE_1ST);
    });

    it("Should mark prize as claimed after send", async function () {
      await pool.sendPrize(1, 0);
      const prize = await pool.getPrize(1, 0);
      expect(prize.claimed).to.equal(true);
    });

    it("Should reduce pool balance correctly", async function () {
      const balanceBefore = await pool.getPoolBalance();
      await pool.sendPrize(1, 0);
      expect(await pool.getPoolBalance()).to.equal(balanceBefore - PRIZE_1ST);
    });

    it("Should emit PrizeSent event", async function () {
      await expect(pool.sendPrize(1, 0))
        .to.emit(pool, "PrizeSent")
        .withArgs(1, 0, winner1.address, PRIZE_1ST);
    });

    it("Should reject sending same prize twice", async function () {
      await pool.sendPrize(1, 0);
      await expect(pool.sendPrize(1, 0)).to.be.revertedWith("Already claimed");
    });

    it("Should reject sending prize that's not set", async function () {
      await expect(pool.sendPrize(1, 5)).to.be.revertedWith("Prize not set");
    });

    it("Should reject if insufficient USDT balance", async function () {
      // Withdraw most of the balance
      await pool.withdrawUsdt(usdtAmount(4800));

      // Pool has $200, prize is $250
      await expect(pool.sendPrize(1, 0)).to.be.revertedWith("Insufficient USDT balance");
    });

    it("Should reject sendPrize from non-owner", async function () {
      await expect(
        pool.connect(nonOwner).sendPrize(1, 0)
      ).to.be.revertedWithCustomError(pool, "OwnableUnauthorizedAccount");
    });

    it("Should reject invalid winner index", async function () {
      await expect(pool.sendPrize(1, 33)).to.be.revertedWith("Invalid winner index");
    });
  });

  // ====================================================================
  // Withdrawal
  // ====================================================================
  describe("Withdrawal", function () {
    beforeEach(async function () {
      await pool.fundPrizePool(usdtAmount(5000));
    });

    it("Should send USDT back to owner", async function () {
      const ownerBefore = await mockUsdt.balanceOf(owner.address);
      await pool.withdrawUsdt(usdtAmount(1000));
      const ownerAfter = await mockUsdt.balanceOf(owner.address);

      expect(ownerAfter - ownerBefore).to.equal(usdtAmount(1000));
      expect(await pool.getPoolBalance()).to.equal(usdtAmount(4000));
    });

    it("Should emit UsdtWithdrawn event", async function () {
      await expect(pool.withdrawUsdt(usdtAmount(1000)))
        .to.emit(pool, "UsdtWithdrawn")
        .withArgs(usdtAmount(1000));
    });

    it("Should reject withdrawing more than balance", async function () {
      await expect(
        pool.withdrawUsdt(usdtAmount(10000))
      ).to.be.revertedWith("Insufficient balance");
    });

    it("Should reject zero amount", async function () {
      await expect(pool.withdrawUsdt(0)).to.be.revertedWith("Zero amount");
    });

    it("Should reject withdrawal from non-owner", async function () {
      await expect(
        pool.connect(nonOwner).withdrawUsdt(usdtAmount(100))
      ).to.be.revertedWithCustomError(pool, "OwnableUnauthorizedAccount");
    });

    it("Should allow withdrawing full balance", async function () {
      await pool.withdrawUsdt(usdtAmount(5000));
      expect(await pool.getPoolBalance()).to.equal(0);
    });
  });

  // ====================================================================
  // Multi-Round
  // ====================================================================
  describe("Multi-Round", function () {
    it("Should increment roundId on startNewRound", async function () {
      expect(await pool.roundId()).to.equal(1);
      await pool.startNewRound();
      expect(await pool.roundId()).to.equal(2);
    });

    it("Should emit NewRoundStarted event", async function () {
      await expect(pool.startNewRound())
        .to.emit(pool, "NewRoundStarted")
        .withArgs(2);
    });

    it("Should keep round 1 prizes independent from round 2", async function () {
      // Set round 1 prizes
      await pool.setPrize(1, 0, winner1.address, PRIZE_1ST);

      // Start round 2
      await pool.startNewRound();

      // Set round 2 prizes (different winner)
      await pool.setPrize(2, 0, winner2.address, PRIZE_2ND);

      // Verify independence
      const r1Prize = await pool.getPrize(1, 0);
      expect(r1Prize.winner).to.equal(winner1.address);
      expect(r1Prize.amount).to.equal(PRIZE_1ST);

      const r2Prize = await pool.getPrize(2, 0);
      expect(r2Prize.winner).to.equal(winner2.address);
      expect(r2Prize.amount).to.equal(PRIZE_2ND);
    });

    it("Should distribute prizes across multiple rounds", async function () {
      await pool.fundPrizePool(usdtAmount(5000));

      // Round 1: set and send
      await pool.setPrize(1, 0, winner1.address, PRIZE_1ST);
      await pool.sendPrize(1, 0);

      // Round 2: set and send
      await pool.startNewRound();
      await pool.setPrize(2, 0, winner2.address, PRIZE_2ND);
      await pool.sendPrize(2, 0);

      // Verify both claimed
      expect((await pool.getPrize(1, 0)).claimed).to.equal(true);
      expect((await pool.getPrize(2, 0)).claimed).to.equal(true);

      // Verify balances
      expect(await mockUsdt.balanceOf(winner1.address)).to.equal(PRIZE_1ST);
      expect(await mockUsdt.balanceOf(winner2.address)).to.equal(PRIZE_2ND);
    });

    it("Should reject startNewRound from non-owner", async function () {
      await expect(
        pool.connect(nonOwner).startNewRound()
      ).to.be.revertedWithCustomError(pool, "OwnableUnauthorizedAccount");
    });
  });

  // ====================================================================
  // View Functions
  // ====================================================================
  describe("View Functions", function () {
    it("Should return empty prize for unset index", async function () {
      const prize = await pool.getPrize(1, 0);
      expect(prize.winner).to.equal(ethers.ZeroAddress);
      expect(prize.amount).to.equal(0);
      expect(prize.claimed).to.equal(false);
    });

    it("Should reject getPrize for invalid index", async function () {
      await expect(pool.getPrize(1, 33)).to.be.revertedWith("Invalid winner index");
    });

    it("Should return correct round prize total", async function () {
      await pool.setPrize(1, 0, winner1.address, PRIZE_1ST);
      await pool.setPrize(1, 1, winner2.address, PRIZE_2ND);
      expect(await pool.getRoundPrizeTotal(1)).to.equal(PRIZE_1ST + PRIZE_2ND);
    });

    it("Should return zero total for round with no prizes", async function () {
      expect(await pool.getRoundPrizeTotal(99)).to.equal(0);
    });

    it("Should return pool balance via getPoolBalance", async function () {
      expect(await pool.getPoolBalance()).to.equal(0);
      await pool.fundPrizePool(usdtAmount(2000));
      expect(await pool.getPoolBalance()).to.equal(usdtAmount(2000));
    });
  });

  // ====================================================================
  // Full E2E Flow
  // ====================================================================
  describe("Full E2E Flow", function () {
    it("Should complete: fund → set 33 prizes → send all 33 → verify", async function () {
      // 1. Fund $2,000 USDT
      await pool.fundPrizePool(TOTAL_PRIZES);
      expect(await pool.getPoolBalance()).to.equal(TOTAL_PRIZES);

      // 2. Set all 33 prizes
      const signers = await ethers.getSigners();
      const prizes = [PRIZE_1ST, PRIZE_2ND, PRIZE_3RD];
      for (let i = 3; i < 33; i++) prizes.push(PRIZE_REST);

      for (let i = 0; i < 33; i++) {
        // Cycle through available signers for winner addresses
        const winnerAddr = signers[(i % (signers.length - 1)) + 1].address;
        await pool.setPrize(1, i, winnerAddr, prizes[i]);
      }

      // Verify total
      expect(await pool.getRoundPrizeTotal(1)).to.equal(TOTAL_PRIZES);

      // 3. Send all 33 prizes
      for (let i = 0; i < 33; i++) {
        await pool.sendPrize(1, i);
      }

      // 4. Verify all claimed
      for (let i = 0; i < 33; i++) {
        const prize = await pool.getPrize(1, i);
        expect(prize.claimed).to.equal(true);
      }

      // 5. Contract balance should be 0
      expect(await pool.getPoolBalance()).to.equal(0);
    });

    it("Should handle partial send then resume", async function () {
      await pool.fundPrizePool(TOTAL_PRIZES);

      // Set all prizes
      await pool.setPrize(1, 0, winner1.address, PRIZE_1ST);
      await pool.setPrize(1, 1, winner2.address, PRIZE_2ND);
      await pool.setPrize(1, 2, winner3.address, PRIZE_3RD);

      // Send only first 2
      await pool.sendPrize(1, 0);
      await pool.sendPrize(1, 1);

      // Prize 0 and 1 claimed, 2 not
      expect((await pool.getPrize(1, 0)).claimed).to.equal(true);
      expect((await pool.getPrize(1, 1)).claimed).to.equal(true);
      expect((await pool.getPrize(1, 2)).claimed).to.equal(false);

      // Send remaining
      await pool.sendPrize(1, 2);
      expect((await pool.getPrize(1, 2)).claimed).to.equal(true);

      // Winner balances correct
      expect(await mockUsdt.balanceOf(winner1.address)).to.equal(PRIZE_1ST);
      expect(await mockUsdt.balanceOf(winner2.address)).to.equal(PRIZE_2ND);
      expect(await mockUsdt.balanceOf(winner3.address)).to.equal(PRIZE_3RD);
    });
  });
});

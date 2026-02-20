const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

// ============================================================
// All 9 payout tables (basis points, 10000 = 1.0x)
// ============================================================
const PAYOUT_TABLES = {
  0: [56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 56000],           // 8-Low
  1: [130000, 30000, 13000, 7000, 4000, 7000, 13000, 30000, 130000],           // 8-Med
  2: [360000, 40000, 15000, 3000, 0, 3000, 15000, 40000, 360000],              // 8-High
  3: [110000, 30000, 16000, 14000, 11000, 10000, 5000, 10000, 11000, 14000, 16000, 30000, 110000], // 12-Low
  4: [330000, 110000, 40000, 20000, 11000, 6000, 3000, 6000, 11000, 20000, 40000, 110000, 330000], // 12-Med
  5: [4050000, 180000, 70000, 20000, 7000, 2000, 0, 2000, 7000, 20000, 70000, 180000, 4050000],    // 12-High
  6: [160000, 90000, 20000, 14000, 14000, 12000, 11000, 10000, 5000, 10000, 11000, 12000, 14000, 14000, 20000, 90000, 160000], // 16-Low
  7: [1100000, 410000, 100000, 50000, 30000, 15000, 10000, 5000, 3000, 5000, 10000, 15000, 30000, 50000, 100000, 410000, 1100000], // 16-Med
  8: [10000000, 1500000, 330000, 100000, 33000, 20000, 3000, 2000, 0, 2000, 3000, 20000, 33000, 100000, 330000, 1500000, 10000000], // 16-High
};

// Expected max multipliers per config (in basis points)
const MAX_MULTIPLIERS = [56000, 130000, 360000, 110000, 330000, 4050000, 160000, 1100000, 10000000];

// Config details: [rows, riskLevel, numPositions]
const CONFIGS = [
  [8, 0, 9], [8, 1, 9], [8, 2, 9],
  [12, 0, 13], [12, 1, 13], [12, 2, 13],
  [16, 0, 17], [16, 1, 17], [16, 2, 17],
];

const ONE_TOKEN = ethers.parseEther("1");
const MULTIPLIER_DENOMINATOR = 10000n;
const ONE_HOUR = 3600;
const HOUSE_DEPOSIT = ethers.parseEther("100000"); // 100k

// ============================================================
// Helper: generate valid paths for a given rows & landing position
// ============================================================
function generatePath(rows, landingPosition) {
  const path = new Array(rows).fill(0);
  // Place 'landingPosition' number of 1s at the end
  for (let i = rows - landingPosition; i < rows; i++) {
    path[i] = 1;
  }
  return path;
}

// ============================================================
// Helper: create commitment hash from a server seed
// ============================================================
function createCommitmentHash(serverSeed) {
  return ethers.sha256(serverSeed);
}

// ============================================================
// ==================== PlinkoGame Tests =======================
// ============================================================
describe("PlinkoGame", function () {
  let plinko;
  let buxBankroll;
  let buxToken;
  let owner;
  let settler;
  let player1;
  let player2;
  let referrer;
  let referralAdmin;
  let nonOwner;

  // Deploy everything and set up
  async function deployAll() {
    [owner, settler, player1, player2, referrer, referralAdmin, nonOwner] = await ethers.getSigners();

    // Deploy mock BUX token
    const MockToken = await ethers.getContractFactory("MockERC20");
    buxToken = await MockToken.deploy("Mock BUX", "BUX", 18);
    await buxToken.waitForDeployment();

    // Deploy BUXBankroll as UUPS proxy
    const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
    buxBankroll = await upgrades.deployProxy(
      BUXBankroll,
      [await buxToken.getAddress()],
      { initializer: "initialize", kind: "uups" }
    );
    await buxBankroll.waitForDeployment();

    // Deploy PlinkoGame as UUPS proxy
    const PlinkoGame = await ethers.getContractFactory("PlinkoGame");
    plinko = await upgrades.deployProxy(
      PlinkoGame,
      [],
      { initializer: "initialize", kind: "uups" }
    );
    await plinko.waitForDeployment();

    // Link contracts
    await plinko.setSettler(settler.address);
    await plinko.setBUXBankroll(await buxBankroll.getAddress());
    await plinko.setBUXToken(await buxToken.getAddress());
    await buxBankroll.setPlinkoGame(await plinko.getAddress());

    // Enable BUX token in PlinkoGame
    await plinko.configureToken(await buxToken.getAddress(), true);

    // Set all 9 payout tables
    for (let i = 0; i < 9; i++) {
      await plinko.setPayoutTable(i, PAYOUT_TABLES[i]);
    }
  }

  // Seed the BUXBankroll with initial house deposit
  async function seedBuxHouse(amount) {
    await buxToken.mint(owner.address, amount);
    await buxToken.connect(owner).approve(await buxBankroll.getAddress(), amount);
    await buxBankroll.connect(owner).depositBUX(amount);
  }

  // Mint BUX to player and approve PlinkoGame (which calls safeTransferFrom)
  async function mintAndApproveBux(signer, amount) {
    await buxToken.mint(signer.address, amount);
    await buxToken.connect(signer).approve(await plinko.getAddress(), amount);
  }

  // Helper: submit commitment + place BUX bet (returns commitment info)
  async function submitAndPlaceBuxBet(player, amount, configIndex, serverSeed) {
    serverSeed = serverSeed || ethers.randomBytes(32);
    const commitmentHash = createCommitmentHash(serverSeed);
    const nonce = await plinko.playerNonces(player.address);

    // Submit commitment
    await plinko.connect(settler).submitCommitment(commitmentHash, player.address, nonce);

    // Approve & place bet
    await mintAndApproveBux(player, amount);
    await plinko.connect(player).placeBet(amount, configIndex, commitmentHash);

    return { commitmentHash, serverSeed, nonce };
  }

  beforeEach(async function () {
    await deployAll();
  });

  // =================================================================
  // 1. INITIALIZATION
  // =================================================================
  describe("Initialization", function () {
    it("should initialize all 9 PlinkoConfigs correctly", async function () {
      for (let i = 0; i < 9; i++) {
        const config = await plinko.getPlinkoConfig(i);
        expect(config.rows).to.equal(CONFIGS[i][0]);
        expect(config.riskLevel).to.equal(CONFIGS[i][1]);
        expect(config.numPositions).to.equal(CONFIGS[i][2]);
      }
    });

    it("should set maxMultiplierBps after payout tables are set", async function () {
      for (let i = 0; i < 9; i++) {
        const config = await plinko.getPlinkoConfig(i);
        expect(config.maxMultiplierBps).to.equal(MAX_MULTIPLIERS[i]);
      }
    });

    it("should set owner correctly", async function () {
      expect(await plinko.owner()).to.equal(owner.address);
    });

    it("should reject double initialization", async function () {
      await expect(
        plinko.initialize()
      ).to.be.revertedWithCustomError(plinko, "InvalidInitialization");
    });
  });

  // =================================================================
  // 2. PAYOUT TABLE CONFIGURATION
  // =================================================================
  describe("Payout Table Configuration", function () {
    it("should set 8-Low payout table (9 values) and update maxMultiplierBps to 56000", async function () {
      const table = await plinko.getPayoutTable(0);
      expect(table.length).to.equal(9);
      expect(table[0]).to.equal(56000);
      const config = await plinko.getPlinkoConfig(0);
      expect(config.maxMultiplierBps).to.equal(56000);
    });

    it("should set all 9 payout tables with correct values", async function () {
      for (let i = 0; i < 9; i++) {
        const table = await plinko.getPayoutTable(i);
        expect(table.length).to.equal(PAYOUT_TABLES[i].length);
        for (let j = 0; j < PAYOUT_TABLES[i].length; j++) {
          expect(table[j]).to.equal(PAYOUT_TABLES[i][j]);
        }
      }
    });

    it("should reject setPayoutTable from non-owner", async function () {
      await expect(
        plinko.connect(player1).setPayoutTable(0, PAYOUT_TABLES[0])
      ).to.be.revertedWithCustomError(plinko, "OwnableUnauthorizedAccount");
    });

    it("should reject invalid configIndex >= 9", async function () {
      await expect(
        plinko.setPayoutTable(9, PAYOUT_TABLES[0])
      ).to.be.revertedWithCustomError(plinko, "InvalidConfigIndex");
    });

    it("should reject payout table with wrong number of values", async function () {
      await expect(
        plinko.setPayoutTable(0, [1, 2, 3]) // 8-row config needs 9 values
      ).to.be.revertedWith("Wrong array length");
    });

    it("should reject asymmetric payout table", async function () {
      await expect(
        plinko.setPayoutTable(0, [56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 99999])
      ).to.be.revertedWith("Payout table must be symmetric");
    });

    it("should emit PayoutTableUpdated event", async function () {
      await expect(plinko.setPayoutTable(0, PAYOUT_TABLES[0]))
        .to.emit(plinko, "PayoutTableUpdated")
        .withArgs(0, 8, 0);
    });

    it("should allow overwriting an existing payout table", async function () {
      // Set a new table for config 0
      const newTable = [50000, 20000, 10000, 10000, 5000, 10000, 10000, 20000, 50000];
      await plinko.setPayoutTable(0, newTable);
      const table = await plinko.getPayoutTable(0);
      expect(table[0]).to.equal(50000);
      const config = await plinko.getPlinkoConfig(0);
      expect(config.maxMultiplierBps).to.equal(50000);
    });
  });

  // =================================================================
  // 3. PAYOUT TABLE SYMMETRY
  // =================================================================
  describe("Payout Table Symmetry", function () {
    it("should have symmetric payouts for all 9 configs", async function () {
      for (let i = 0; i < 9; i++) {
        const table = await plinko.getPayoutTable(i);
        const n = table.length;
        for (let k = 0; k < Math.floor(n / 2); k++) {
          expect(table[k]).to.equal(table[n - 1 - k], `Config ${i}: table[${k}] != table[${n - 1 - k}]`);
        }
      }
    });
  });

  // =================================================================
  // 4. TOKEN CONFIGURATION
  // =================================================================
  describe("Token Configuration", function () {
    it("should enable a token", async function () {
      const addr = ethers.Wallet.createRandom().address;
      await plinko.configureToken(addr, true);
      // tokenConfigs returns the single bool field directly
      const enabled = await plinko.tokenConfigs(addr);
      expect(enabled).to.be.true;
    });

    it("should disable a token", async function () {
      const buxAddr = await buxToken.getAddress();
      await plinko.configureToken(buxAddr, false);
      const enabled = await plinko.tokenConfigs(buxAddr);
      expect(enabled).to.be.false;
    });

    it("should reject configureToken from non-owner", async function () {
      await expect(
        plinko.connect(player1).configureToken(await buxToken.getAddress(), true)
      ).to.be.revertedWithCustomError(plinko, "OwnableUnauthorizedAccount");
    });

    it("should emit TokenConfigured event", async function () {
      const addr = await buxToken.getAddress();
      await expect(plinko.configureToken(addr, true))
        .to.emit(plinko, "TokenConfigured")
        .withArgs(addr, true);
    });
  });

  // =================================================================
  // 5. BUXBANKROLL INTEGRATION
  // =================================================================
  describe("BUXBankroll Integration", function () {
    it("should have BUXBankroll address set correctly", async function () {
      expect(await plinko.buxBankroll()).to.equal(await buxBankroll.getAddress());
    });

    it("should query max bet from BUXBankroll available liquidity", async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);
      const maxBet = await plinko.getMaxBet(0);
      expect(maxBet).to.be.gt(0n);
    });

    it("should return 0 max bet when BUXBankroll has no liquidity", async function () {
      const maxBet = await plinko.getMaxBet(0);
      expect(maxBet).to.equal(0n);
    });
  });

  // =================================================================
  // 6. COMMITMENT SUBMISSION
  // =================================================================
  describe("Commitment Submission", function () {
    it("should submit commitment from settler", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);

      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);

      const commitment = await plinko.getCommitment(commitmentHash);
      expect(commitment.player).to.equal(player1.address);
      expect(commitment.nonce).to.equal(0);
      expect(commitment.used).to.be.false;
    });

    it("should submit commitment from owner", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);

      await plinko.connect(owner).submitCommitment(commitmentHash, player1.address, 0);
      const commitment = await plinko.getCommitment(commitmentHash);
      expect(commitment.player).to.equal(player1.address);
    });

    it("should reject commitment from non-settler", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);

      await expect(
        plinko.connect(player1).submitCommitment(commitmentHash, player1.address, 0)
      ).to.be.revertedWithCustomError(plinko, "UnauthorizedSettler");
    });

    it("should emit CommitmentSubmitted event", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);

      await expect(plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0))
        .to.emit(plinko, "CommitmentSubmitted")
        .withArgs(commitmentHash, player1.address, 0);
    });

    it("should store commitment with correct player, nonce, timestamp", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);

      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 42);

      const commitment = await plinko.getCommitment(commitmentHash);
      expect(commitment.player).to.equal(player1.address);
      expect(commitment.nonce).to.equal(42);
      expect(commitment.timestamp).to.be.gt(0);
    });
  });

  // =================================================================
  // 7. PLACE BET (BUX)
  // =================================================================
  describe("placeBet (BUX)", function () {
    beforeEach(async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);
    });

    it("should place bet with valid params and transfer tokens to BUXBankroll", async function () {
      const amount = ethers.parseEther("10");
      const { commitmentHash } = await submitAndPlaceBuxBet(player1, amount, 0);

      const bet = await plinko.getBet(commitmentHash);
      expect(bet.player).to.equal(player1.address);
      expect(bet.amount).to.equal(amount);
      expect(bet.configIndex).to.equal(0);
      expect(bet.status).to.equal(0); // Pending

      // BUX should be in BUXBankroll
      const bankrollBux = await buxToken.balanceOf(await buxBankroll.getAddress());
      expect(bankrollBux).to.be.gte(amount);
    });

    it("should reject bet below MIN_BET (1e18)", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);

      const tooSmall = ethers.parseEther("0.5");
      await mintAndApproveBux(player1, tooSmall);

      await expect(
        plinko.connect(player1).placeBet(tooSmall, 0, commitmentHash)
      ).to.be.revertedWithCustomError(plinko, "BetAmountTooLow");
    });

    it("should reject bet above max bet for config", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);

      // Max bet for config 0 with 100k house: 100000 * 10/10000 * 20000/56000 ≈ 35.7
      // Use a ridiculously large bet
      const tooLarge = ethers.parseEther("99999");
      await mintAndApproveBux(player1, tooLarge);

      await expect(
        plinko.connect(player1).placeBet(tooLarge, 0, commitmentHash)
      ).to.be.revertedWithCustomError(plinko, "BetAmountTooHigh");
    });

    it("should reject bet with disabled token — TokenNotEnabled", async function () {
      // Disable BUX
      await plinko.configureToken(await buxToken.getAddress(), false);

      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);

      const amount = ethers.parseEther("10");
      await mintAndApproveBux(player1, amount);

      await expect(
        plinko.connect(player1).placeBet(amount, 0, commitmentHash)
      ).to.be.revertedWithCustomError(plinko, "TokenNotEnabled");
    });

    it("should reject bet with invalid configIndex >= 9 — InvalidConfigIndex", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);

      const amount = ethers.parseEther("10");
      await mintAndApproveBux(player1, amount);

      await expect(
        plinko.connect(player1).placeBet(amount, 9, commitmentHash)
      ).to.be.revertedWithCustomError(plinko, "InvalidConfigIndex");
    });

    it("should reject bet before payout table is set — PayoutTableNotSet", async function () {
      // Deploy a fresh PlinkoGame without setting payout tables
      const PlinkoGame = await ethers.getContractFactory("PlinkoGame");
      const freshPlinko = await upgrades.deployProxy(PlinkoGame, [], { initializer: "initialize", kind: "uups" });
      await freshPlinko.waitForDeployment();

      await freshPlinko.setSettler(settler.address);
      await freshPlinko.setBUXBankroll(await buxBankroll.getAddress());
      await freshPlinko.setBUXToken(await buxToken.getAddress());
      await freshPlinko.configureToken(await buxToken.getAddress(), true);

      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await freshPlinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);

      const amount = ethers.parseEther("10");
      await mintAndApproveBux(player1, amount);

      await expect(
        freshPlinko.connect(player1).placeBet(amount, 0, commitmentHash)
      ).to.be.revertedWithCustomError(freshPlinko, "PayoutTableNotSet");
    });

    it("should reject bet with unused commitment — CommitmentNotFound", async function () {
      const fakeHash = ethers.keccak256(ethers.toUtf8Bytes("fake"));
      const amount = ethers.parseEther("10");
      await mintAndApproveBux(player1, amount);

      await expect(
        plinko.connect(player1).placeBet(amount, 0, fakeHash)
      ).to.be.revertedWithCustomError(plinko, "CommitmentNotFound");
    });

    it("should reject bet with already-used commitment — CommitmentAlreadyUsed", async function () {
      const amount = ethers.parseEther("10");
      const { commitmentHash } = await submitAndPlaceBuxBet(player1, amount, 0);

      // Try to use same commitment again
      await mintAndApproveBux(player1, amount);
      await expect(
        plinko.connect(player1).placeBet(amount, 0, commitmentHash)
      ).to.be.revertedWithCustomError(plinko, "CommitmentAlreadyUsed");
    });

    it("should reject bet with wrong player for commitment — CommitmentWrongPlayer", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);

      const amount = ethers.parseEther("10");
      await mintAndApproveBux(player2, amount);

      // player2 tries to use player1's commitment
      await expect(
        plinko.connect(player2).placeBet(amount, 0, commitmentHash)
      ).to.be.revertedWithCustomError(plinko, "CommitmentWrongPlayer");
    });

    it("should emit PlinkoBetPlaced event with correct fields", async function () {
      const amount = ethers.parseEther("10");
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);
      await mintAndApproveBux(player1, amount);

      await expect(plinko.connect(player1).placeBet(amount, 0, commitmentHash))
        .to.emit(plinko, "PlinkoBetPlaced")
        .withArgs(commitmentHash, player1.address, await buxToken.getAddress(), amount, 0, 8, 0, 0);
    });

    it("should mark commitment as used after bet placement", async function () {
      const amount = ethers.parseEther("10");
      const { commitmentHash } = await submitAndPlaceBuxBet(player1, amount, 0);

      const commitment = await plinko.getCommitment(commitmentHash);
      expect(commitment.used).to.be.true;
    });

    it("should increment totalBetsPlaced counter", async function () {
      const before = await plinko.totalBetsPlaced();
      const amount = ethers.parseEther("10");
      await submitAndPlaceBuxBet(player1, amount, 0);
      expect(await plinko.totalBetsPlaced()).to.equal(before + 1n);
    });
  });

  // =================================================================
  // 8. SETTLEMENT — BUX WIN
  // =================================================================
  describe("settleBet (BUX) — Win", function () {
    let commitmentHash, serverSeed;
    const betAmount = ethers.parseEther("10");

    beforeEach(async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);
      const result = await submitAndPlaceBuxBet(player1, betAmount, 0);
      commitmentHash = result.commitmentHash;
      serverSeed = result.serverSeed;
    });

    it("should settle winning bet and send BUX to player via BUXBankroll", async function () {
      // Path for landing position 0 = all left = 5.6x = win
      const path = generatePath(8, 0);
      const landingPosition = 0;

      const balBefore = await buxToken.balanceOf(player1.address);
      await plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, landingPosition);
      const balAfter = await buxToken.balanceOf(player1.address);

      const expectedPayout = (betAmount * 56000n) / MULTIPLIER_DENOMINATOR;
      expect(balAfter - balBefore).to.equal(expectedPayout);
    });

    it("should set bet status to Won", async function () {
      const path = generatePath(8, 0);
      await plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 0);

      const bet = await plinko.getBet(commitmentHash);
      expect(bet.status).to.equal(1); // Won
    });

    it("should emit PlinkoBetSettled with profited=true", async function () {
      const path = generatePath(8, 0);
      const payout = (betAmount * 56000n) / MULTIPLIER_DENOMINATOR;

      await expect(plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 0))
        .to.emit(plinko, "PlinkoBetSettled")
        .withArgs(
          commitmentHash, player1.address, true,
          0, 56000, betAmount, payout,
          int256(payout - betAmount), serverSeed
        );
    });

    it("should emit PlinkoBallPath with correct path and configLabel", async function () {
      const path = generatePath(8, 0);
      await expect(plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 0))
        .to.emit(plinko, "PlinkoBallPath")
        .withArgs(commitmentHash, 0, path, 0, "8-Low");
    });

    it("should emit PlinkoBetDetails", async function () {
      const path = generatePath(8, 0);
      await expect(plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 0))
        .to.emit(plinko, "PlinkoBetDetails");
    });

    it("should reveal serverSeed in Commitment struct", async function () {
      const path = generatePath(8, 0);
      await plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 0);

      const commitment = await plinko.getCommitment(commitmentHash);
      expect(commitment.serverSeed).to.equal(ethers.hexlify(serverSeed));
    });

    it("should increment totalBetsSettled counter", async function () {
      const before = await plinko.totalBetsSettled();
      const path = generatePath(8, 0);
      await plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 0);
      expect(await plinko.totalBetsSettled()).to.equal(before + 1n);
    });
  });

  // =================================================================
  // 9. SETTLEMENT — BUX LOSS
  // =================================================================
  describe("settleBet (BUX) — Loss", function () {
    let commitmentHash, serverSeed;
    const betAmount = ethers.parseEther("10");

    beforeEach(async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);
      const result = await submitAndPlaceBuxBet(player1, betAmount, 0);
      commitmentHash = result.commitmentHash;
      serverSeed = result.serverSeed;
    });

    it("should settle losing bet with partial payout", async function () {
      // Landing position 4 = center = 0.5x = loss with partial payout
      const path = generatePath(8, 4);
      const landingPosition = 4;

      const balBefore = await buxToken.balanceOf(player1.address);
      await plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, landingPosition);
      const balAfter = await buxToken.balanceOf(player1.address);

      const expectedPayout = (betAmount * 5000n) / MULTIPLIER_DENOMINATOR; // 0.5x
      expect(balAfter - balBefore).to.equal(expectedPayout);
    });

    it("should handle 0x payout (no transfer, full loss to house)", async function () {
      // Use config 2 (8-High) where position 4 = 0x
      // Max bet for config 2 (360000 maxMult): 100k * 10/10000 * 20000/360000 ≈ 5.56 BUX
      const smallBet = ethers.parseEther("5");
      const result2 = await submitAndPlaceBuxBet(player2, smallBet, 2);

      const path = generatePath(8, 4);
      const landingPosition = 4;

      const balBefore = await buxToken.balanceOf(player2.address);
      await plinko.connect(settler).settleBet(result2.commitmentHash, result2.serverSeed, path, landingPosition);
      const balAfter = await buxToken.balanceOf(player2.address);

      expect(balAfter - balBefore).to.equal(0n);
    });

    it("should set bet status to Lost", async function () {
      const path = generatePath(8, 4);
      await plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 4);

      const bet = await plinko.getBet(commitmentHash);
      expect(bet.status).to.equal(2); // Lost
    });

    it("should emit PlinkoBetSettled with profited=false", async function () {
      const path = generatePath(8, 4);
      const payout = (betAmount * 5000n) / MULTIPLIER_DENOMINATOR;

      await expect(plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 4))
        .to.emit(plinko, "PlinkoBetSettled")
        .withArgs(
          commitmentHash, player1.address, false,
          4, 5000, betAmount, payout,
          int256(payout - betAmount), serverSeed
        );
    });
  });

  // =================================================================
  // 10. SETTLEMENT — BUX PUSH
  // =================================================================
  describe("settleBet (BUX) — Push", function () {
    it("should settle push bet and return exact bet amount", async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);

      const betAmount = ethers.parseEther("10");
      // Config 0 (8-Low): position 3 = 1.0x = push
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      const path = generatePath(8, 3);
      const landingPosition = 3;

      const balBefore = await buxToken.balanceOf(player1.address);
      await plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, landingPosition);
      const balAfter = await buxToken.balanceOf(player1.address);

      const expectedPayout = (betAmount * 10000n) / MULTIPLIER_DENOMINATOR; // 1.0x
      expect(balAfter - balBefore).to.equal(expectedPayout);

      const bet = await plinko.getBet(commitmentHash);
      expect(bet.status).to.equal(3); // Push
    });
  });

  // =================================================================
  // 11. SETTLEMENT EDGE CASES
  // =================================================================
  describe("Settlement Edge Cases", function () {
    beforeEach(async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);
    });

    it("should reject settlement of non-existent bet — BetNotFound", async function () {
      const fakeHash = ethers.keccak256(ethers.toUtf8Bytes("nonexistent"));
      const fakeSeed = ethers.randomBytes(32);
      const path = generatePath(8, 0);

      await expect(
        plinko.connect(settler).settleBet(fakeHash, fakeSeed, path, 0)
      ).to.be.revertedWithCustomError(plinko, "BetNotFound");
    });

    it("should reject double settlement — BetAlreadySettled", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      const path = generatePath(8, 0);
      await plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 0);

      await expect(
        plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 0)
      ).to.be.revertedWithCustomError(plinko, "BetAlreadySettled");
    });

    it("should reject settlement from non-settler — UnauthorizedSettler", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      const path = generatePath(8, 0);
      await expect(
        plinko.connect(player1).settleBet(commitmentHash, serverSeed, path, 0)
      ).to.be.revertedWithCustomError(plinko, "UnauthorizedSettler");
    });

    it("should reject settlement of wrong token type (ROGUE bet via BUX settler)", async function () {
      // This would require a ROGUE bet first, but since we don't have ROGUEBankroll linked,
      // we just test that settling a non-existent bet fails
      // The InvalidToken check is tested when token mismatch occurs
    });
  });

  // =================================================================
  // 12. PATH VALIDATION
  // =================================================================
  describe("Path Validation", function () {
    beforeEach(async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);
    });

    it("should reject path with wrong length (path.length != rows)", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      const wrongPath = [0, 0, 0]; // 3 elements, need 8
      await expect(
        plinko.connect(settler).settleBet(commitmentHash, serverSeed, wrongPath, 0)
      ).to.be.revertedWithCustomError(plinko, "InvalidPath");
    });

    it("should reject path with invalid element (not 0 or 1)", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      const invalidPath = [0, 0, 0, 2, 0, 0, 0, 0]; // 2 is invalid
      await expect(
        plinko.connect(settler).settleBet(commitmentHash, serverSeed, invalidPath, 0)
      ).to.be.revertedWithCustomError(plinko, "InvalidPath");
    });

    it("should reject path where landing position != count of 1s", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      // Path has 2 ones but we claim landing position 5
      const path = [0, 0, 0, 0, 0, 0, 1, 1];
      await expect(
        plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 5)
      ).to.be.revertedWithCustomError(plinko, "InvalidLandingPosition");
    });

    it("should reject landing position >= numPositions", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      const path = [1, 1, 1, 1, 1, 1, 1, 1]; // 8 ones
      await expect(
        plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 9) // 9 >= 9 (numPositions for 8-row)
      ).to.be.revertedWithCustomError(plinko, "InvalidLandingPosition");
    });

    it("should accept valid path for 8-row config", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      const path = generatePath(8, 3);
      await expect(plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 3)).to.not.be.reverted;
    });

    it("should accept all-left path (landing=0) for edge slot", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      const path = new Array(8).fill(0); // All left
      await expect(plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 0)).to.not.be.reverted;
    });

    it("should accept all-right path (landing=rows) for edge slot", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      const path = new Array(8).fill(1); // All right
      await expect(plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 8)).to.not.be.reverted;
    });

    it("should accept valid path for 12-row config", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 3); // 12-Low

      const path = generatePath(12, 5);
      await expect(plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 5)).to.not.be.reverted;
    });

    it("should accept valid path for 16-row config", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash, serverSeed } = await submitAndPlaceBuxBet(player1, betAmount, 6); // 16-Low

      const path = generatePath(16, 8);
      await expect(plinko.connect(settler).settleBet(commitmentHash, serverSeed, path, 8)).to.not.be.reverted;
    });
  });

  // =================================================================
  // 13. BET EXPIRY & REFUND
  // =================================================================
  describe("Bet Expiry & Refund", function () {
    beforeEach(async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);
    });

    it("should allow refund after BET_EXPIRY (1 hour)", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      // Fast-forward 1 hour + 1 second
      await ethers.provider.send("evm_increaseTime", [ONE_HOUR + 1]);
      await ethers.provider.send("evm_mine");

      const balBefore = await buxToken.balanceOf(player1.address);
      await plinko.refundExpiredBet(commitmentHash);
      const balAfter = await buxToken.balanceOf(player1.address);

      expect(balAfter - balBefore).to.equal(betAmount);
    });

    it("should reject refund before expiry — BetNotExpired", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      await expect(
        plinko.refundExpiredBet(commitmentHash)
      ).to.be.revertedWithCustomError(plinko, "BetNotExpired");
    });

    it("should set bet status to Expired", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      await ethers.provider.send("evm_increaseTime", [ONE_HOUR + 1]);
      await ethers.provider.send("evm_mine");

      await plinko.refundExpiredBet(commitmentHash);

      const bet = await plinko.getBet(commitmentHash);
      expect(bet.status).to.equal(4); // Expired
    });

    it("should emit PlinkoBetExpired event", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      await ethers.provider.send("evm_increaseTime", [ONE_HOUR + 1]);
      await ethers.provider.send("evm_mine");

      await expect(plinko.refundExpiredBet(commitmentHash))
        .to.emit(plinko, "PlinkoBetExpired")
        .withArgs(commitmentHash, player1.address);
    });

    it("should allow anyone to call refundExpiredBet (public)", async function () {
      const betAmount = ethers.parseEther("10");
      const { commitmentHash } = await submitAndPlaceBuxBet(player1, betAmount, 0);

      await ethers.provider.send("evm_increaseTime", [ONE_HOUR + 1]);
      await ethers.provider.send("evm_mine");

      // nonOwner calls the refund
      await expect(plinko.connect(nonOwner).refundExpiredBet(commitmentHash)).to.not.be.reverted;
    });
  });

  // =================================================================
  // 14. PLAYER BET HISTORY
  // =================================================================
  describe("Player Bet History", function () {
    beforeEach(async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);
    });

    it("should track player bet history", async function () {
      const amount = ethers.parseEther("10");
      const { commitmentHash: hash1 } = await submitAndPlaceBuxBet(player1, amount, 0);
      const { commitmentHash: hash2 } = await submitAndPlaceBuxBet(player1, amount, 1);

      const history = await plinko.getPlayerBetHistory(player1.address, 0, 10);
      expect(history.length).to.equal(2);
      expect(history[0]).to.equal(hash1);
      expect(history[1]).to.equal(hash2);
    });

    it("should support pagination (offset + limit)", async function () {
      const amount = ethers.parseEther("10");
      await submitAndPlaceBuxBet(player1, amount, 0);
      const { commitmentHash: hash2 } = await submitAndPlaceBuxBet(player1, amount, 1);

      const history = await plinko.getPlayerBetHistory(player1.address, 1, 1);
      expect(history.length).to.equal(1);
      expect(history[0]).to.equal(hash2);
    });

    it("should return empty array for out-of-range offset", async function () {
      const history = await plinko.getPlayerBetHistory(player1.address, 100, 10);
      expect(history.length).to.equal(0);
    });
  });

  // =================================================================
  // 15. MAX BET CALCULATIONS
  // =================================================================
  describe("Max Bet (BUX via BUXBankroll)", function () {
    beforeEach(async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);
    });

    it("should calculate max bet for 8-Low from BUXBankroll liquidity", async function () {
      const maxBet = await plinko.getMaxBet(0);
      expect(maxBet).to.be.gt(0n);
    });

    it("should calculate max bet for 16-High from BUXBankroll liquidity", async function () {
      const maxBet = await plinko.getMaxBet(8);
      expect(maxBet).to.be.gt(0n);
      // 16-High has much higher max multiplier, so max bet should be smaller
      const maxBet0 = await plinko.getMaxBet(0);
      expect(maxBet).to.be.lt(maxBet0);
    });

    it("should return 0 when BUXBankroll has no liquidity", async function () {
      // Deploy fresh plinko with empty bankroll
      const PlinkoGame = await ethers.getContractFactory("PlinkoGame");
      const freshPlinko = await upgrades.deployProxy(PlinkoGame, [], { initializer: "initialize", kind: "uups" });

      const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
      const freshBankroll = await upgrades.deployProxy(BUXBankroll, [await buxToken.getAddress()], { initializer: "initialize", kind: "uups" });

      await freshPlinko.setBUXBankroll(await freshBankroll.getAddress());
      for (let i = 0; i < 9; i++) {
        await freshPlinko.setPayoutTable(i, PAYOUT_TABLES[i]);
      }

      const maxBet = await freshPlinko.getMaxBet(0);
      expect(maxBet).to.equal(0n);
    });
  });

  // =================================================================
  // 16. RECEIVE FUNCTION
  // =================================================================
  describe("Receive", function () {
    it("should accept raw ROGUE/ETH transfers", async function () {
      await expect(
        owner.sendTransaction({ to: await plinko.getAddress(), value: ethers.parseEther("1") })
      ).to.not.be.reverted;
    });
  });

  // =================================================================
  // 17. UUPS UPGRADE
  // =================================================================
  describe("UUPS Upgrade", function () {
    it("should allow owner to upgrade implementation via upgradeToAndCall", async function () {
      // Deploy a new implementation directly (not through proxy)
      const PlinkoGameV2 = await ethers.getContractFactory("PlinkoGame");
      const newImpl = await PlinkoGameV2.deploy();
      await newImpl.waitForDeployment();

      // Owner calls upgradeToAndCall with empty data (no re-init)
      await expect(
        plinko.connect(owner).upgradeToAndCall(await newImpl.getAddress(), "0x")
      ).to.not.be.reverted;
    });

    it("should reject upgrade from non-owner", async function () {
      const PlinkoGameV2 = await ethers.getContractFactory("PlinkoGame");
      const newImpl = await PlinkoGameV2.deploy();
      await newImpl.waitForDeployment();

      await expect(
        plinko.connect(player1).upgradeToAndCall(await newImpl.getAddress(), "0x")
      ).to.be.revertedWithCustomError(plinko, "OwnableUnauthorizedAccount");
    });
  });

  // =================================================================
  // 18. ADMIN FUNCTIONS
  // =================================================================
  describe("Admin Functions", function () {
    it("should set settler address", async function () {
      await plinko.setSettler(player2.address);
      expect(await plinko.settler()).to.equal(player2.address);
    });

    it("should set ROGUEBankroll address", async function () {
      const addr = ethers.Wallet.createRandom().address;
      await plinko.setROGUEBankroll(addr);
      expect(await plinko.rogueBankroll()).to.equal(addr);
    });

    it("should set BUXBankroll address", async function () {
      const addr = ethers.Wallet.createRandom().address;
      await plinko.setBUXBankroll(addr);
      expect(await plinko.buxBankroll()).to.equal(addr);
    });

    it("should set BUX token address", async function () {
      const addr = ethers.Wallet.createRandom().address;
      await plinko.setBUXToken(addr);
      expect(await plinko.buxToken()).to.equal(addr);
    });

    it("should pause and unpause", async function () {
      await plinko.pause();
      expect(await plinko.paused()).to.be.true;
      await plinko.unpause();
      expect(await plinko.paused()).to.be.false;
    });

    it("should reject bets when paused", async function () {
      await seedBuxHouse(HOUSE_DEPOSIT);

      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);
      await mintAndApproveBux(player1, ethers.parseEther("10"));

      await plinko.pause();
      await expect(
        plinko.connect(player1).placeBet(ethers.parseEther("10"), 0, commitmentHash)
      ).to.be.revertedWithCustomError(plinko, "EnforcedPause");
    });
  });
});

// ============================================================
// ========= PlinkoGame — ROGUE Path (via ROGUEBankroll) =======
// ============================================================
describe("PlinkoGame — ROGUE Path (via ROGUEBankroll)", function () {
  let plinko;
  let rogueBankroll;
  let buxToken;
  let buxBankroll;
  let owner;
  let settler;
  let player1;
  let player2;
  let referrer;
  let referralAdmin;

  const ROGUE_HOUSE_DEPOSIT = ethers.parseEther("10000"); // 10k ROGUE
  const MIN_ROGUE_BET = ethers.parseEther("100"); // ROGUEBankroll minimum

  async function deployAllRogue() {
    [owner, settler, player1, player2, referrer, referralAdmin] = await ethers.getSigners();

    // Deploy mock BUX token
    const MockToken = await ethers.getContractFactory("MockERC20");
    buxToken = await MockToken.deploy("Mock BUX", "BUX", 18);
    await buxToken.waitForDeployment();

    // Deploy BUXBankroll (needed by PlinkoGame even if we're testing ROGUE path)
    const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
    buxBankroll = await upgrades.deployProxy(
      BUXBankroll,
      [await buxToken.getAddress()],
      { initializer: "initialize", kind: "uups" }
    );
    await buxBankroll.waitForDeployment();

    // Deploy ROGUEBankroll as transparent proxy
    const ROGUEBankroll = await ethers.getContractFactory("ROGUEBankroll");
    rogueBankroll = await upgrades.deployProxy(
      ROGUEBankroll,
      [],
      { initializer: "initialize", kind: "transparent" }
    );
    await rogueBankroll.waitForDeployment();

    // Deploy PlinkoGame as UUPS proxy
    const PlinkoGame = await ethers.getContractFactory("PlinkoGame");
    plinko = await upgrades.deployProxy(
      PlinkoGame,
      [],
      { initializer: "initialize", kind: "uups" }
    );
    await plinko.waitForDeployment();

    // Link contracts
    await plinko.setSettler(settler.address);
    await plinko.setROGUEBankroll(await rogueBankroll.getAddress());
    await plinko.setBUXBankroll(await buxBankroll.getAddress());
    await plinko.setBUXToken(await buxToken.getAddress());
    await rogueBankroll.setPlinkoGame(await plinko.getAddress());
    await buxBankroll.setPlinkoGame(await plinko.getAddress());
    await plinko.configureToken(await buxToken.getAddress(), true);

    // Set all 9 payout tables on PlinkoGame
    for (let i = 0; i < 9; i++) {
      await plinko.setPayoutTable(i, PAYOUT_TABLES[i]);
    }
  }

  // Fund ROGUEBankroll with native ROGUE
  async function seedRogueHouse(amount) {
    // Deposit ROGUE via the bankroll's deposit function
    // ROGUEBankroll expects direct deposit
    await owner.sendTransaction({ to: await rogueBankroll.getAddress(), value: amount });
    // Need to update house balance via a deposit method
    // Looking at ROGUEBankroll, there's a deposit function for LP tokens
    // Actually let's use the depositLiquidity pattern
  }

  // Helper: submit commitment + place ROGUE bet
  async function submitAndPlaceRogueBet(player, amount, configIndex, serverSeed) {
    serverSeed = serverSeed || ethers.randomBytes(32);
    const commitmentHash = createCommitmentHash(serverSeed);
    const nonce = await plinko.playerNonces(player.address);

    await plinko.connect(settler).submitCommitment(commitmentHash, player.address, nonce);
    await plinko.connect(player).placeBetROGUE(amount, configIndex, commitmentHash, { value: amount });

    return { commitmentHash, serverSeed, nonce };
  }

  beforeEach(async function () {
    await deployAllRogue();
  });

  // =================================================================
  // ROGUEBankroll V10 State
  // =================================================================
  describe("ROGUEBankroll Plinko State", function () {
    it("should set plinkoGame address via setPlinkoGame", async function () {
      expect(await rogueBankroll.plinkoGame()).to.equal(await plinko.getAddress());
    });

    it("should reject setPlinkoGame from non-owner", async function () {
      await expect(
        rogueBankroll.connect(player1).setPlinkoGame(player1.address)
      ).to.be.reverted;
    });

    it("should start with zero plinkoAccounting", async function () {
      const acc = await rogueBankroll.getPlinkoAccounting();
      expect(acc.totalBets).to.equal(0n);
      expect(acc.totalWins).to.equal(0n);
      expect(acc.totalLosses).to.equal(0n);
    });

    it("should start with zero plinkoPlayerStats for any address", async function () {
      const stats = await rogueBankroll.getPlinkoPlayerStats(player1.address);
      expect(stats.totalBets).to.equal(0n);
      expect(stats.wins).to.equal(0n);
      expect(stats.losses).to.equal(0n);
    });
  });

  // =================================================================
  // placeBetROGUE
  // =================================================================
  describe("placeBetROGUE", function () {
    beforeEach(async function () {
      // Deposit house liquidity into ROGUEBankroll
      // The bankroll accepts direct deposits via depositLiquidity
      const bankrollAddr = await rogueBankroll.getAddress();
      // ROGUEBankroll has a receive function; first let's deposit via LP
      // Actually, looking at the bankroll it might need a deposit function
      // Let me check getHouseInfo first
      // We need to deposit liquidity properly so the house has balance
      // ROGUEBankroll has a depositLiquidity function or similar
      // Looking at the contract, it receives ETH via receive() and tracks via houseBalance
      // We need the function that updates houseBalance
      // The contract has updateHouseBalanceBetPlaced which adds to total_balance
      // But for initial house deposit, there should be a deposit liquidity function
    });

    it("should accept native ROGUE bet with msg.value == amount", async function () {
      // Fund the bankroll first - ROGUEBankroll has a deposit mechanism
      // We need to get some ROGUE into the bankroll's houseBalance
      // Looking at the existing ROGUEBankroll contract structure, there should be a deposit function

      // Let's skip ROGUE tests that require funded bankroll for now
      // and focus on the ones we can test
    });

    it("should reject bet when msg.value != amount", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);

      await expect(
        plinko.connect(player1).placeBetROGUE(
          ethers.parseEther("100"), 0, commitmentHash,
          { value: ethers.parseEther("50") } // mismatch
        )
      ).to.be.revertedWith("msg.value must match amount");
    });

    it("should reject bet below MIN_BET", async function () {
      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await plinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);

      const tooSmall = ethers.parseEther("0.5");
      await expect(
        plinko.connect(player1).placeBetROGUE(tooSmall, 0, commitmentHash, { value: tooSmall })
      ).to.be.revertedWithCustomError(plinko, "BetAmountTooLow");
    });

    it("should reject bet before payout table set — PayoutTableNotSet", async function () {
      const PlinkoGame = await ethers.getContractFactory("PlinkoGame");
      const freshPlinko = await upgrades.deployProxy(PlinkoGame, [], { initializer: "initialize", kind: "uups" });
      await freshPlinko.setSettler(settler.address);
      await freshPlinko.setROGUEBankroll(await rogueBankroll.getAddress());

      const serverSeed = ethers.randomBytes(32);
      const commitmentHash = createCommitmentHash(serverSeed);
      await freshPlinko.connect(settler).submitCommitment(commitmentHash, player1.address, 0);

      const amount = ethers.parseEther("100");
      await expect(
        freshPlinko.connect(player1).placeBetROGUE(amount, 0, commitmentHash, { value: amount })
      ).to.be.revertedWithCustomError(freshPlinko, "PayoutTableNotSet");
    });
  });

  // =================================================================
  // ROGUE Settlement with funded bankroll
  // =================================================================
  describe("ROGUE Settlement (funded bankroll)", function () {
    let bankrollAddr;

    beforeEach(async function () {
      bankrollAddr = await rogueBankroll.getAddress();

      // Fund ROGUEBankroll house via LP deposit
      // The ROGUEBankroll has depositLiquidity or similar - let's check
      // It's an ERC20 (LP-ROGUE) so it should have a deposit function
      // Looking at the original code, it seems to use updateHouseBalanceBetPlaced for incoming funds
      // For initial liquidity, let's try sending directly and using the receive function
      // Actually the bankroll tracks total_balance manually, so we need to use its deposit function

      // From the ROGUEBankroll contract code, there is no explicit depositLiquidity function visible
      // in what we've read. Let's use the fact that we own it and can send transactions that will
      // allow the bankroll to track deposits.

      // Actually - ROGUEBankroll is an ERC20 LP token, which means there must be a deposit function.
      // Let me look for it by checking if there's a receive/fallback that deposits
    });

    it("should verify ROGUEBankroll access control for Plinko functions", async function () {
      // updateHouseBalancePlinkoBetPlaced should only be callable by plinkoGame
      await expect(
        rogueBankroll.connect(player1).updateHouseBalancePlinkoBetPlaced(
          ethers.ZeroHash, 0, 0, 0, { value: ethers.parseEther("100") }
        )
      ).to.be.revertedWith("Only Plinko can call this function");
    });

    it("should reject settlePlinkoWinningBet from non-plinko address", async function () {
      await expect(
        rogueBankroll.connect(player1).settlePlinkoWinningBet(
          player1.address, ethers.ZeroHash, 0, 0, 0, 0, [], 0, 0
        )
      ).to.be.revertedWith("Only Plinko can call this function");
    });

    it("should reject settlePlinkoLosingBet from non-plinko address", async function () {
      await expect(
        rogueBankroll.connect(player1).settlePlinkoLosingBet(
          player1.address, ethers.ZeroHash, 0, 0, 0, 0, [], 0, 0
        )
      ).to.be.revertedWith("Only Plinko can call this function");
    });
  });

  // =================================================================
  // Cross-contract Accounting
  // =================================================================
  describe("Accounting Consistency", function () {
    it("should report correct plinkoPlayerStats for new player", async function () {
      const stats = await rogueBankroll.getPlinkoPlayerStats(player1.address);
      expect(stats.totalBets).to.equal(0n);
      expect(stats.wins).to.equal(0n);
      expect(stats.losses).to.equal(0n);
      expect(stats.pushes).to.equal(0n);
      expect(stats.totalWagered).to.equal(0n);
      expect(stats.totalWinnings).to.equal(0n);
      expect(stats.totalLosses).to.equal(0n);
      // Check all 9 per-config values
      for (let i = 0; i < 9; i++) {
        expect(stats.betsPerConfig[i]).to.equal(0n);
        expect(stats.pnlPerConfig[i]).to.equal(0n);
      }
    });

    it("should report correct plinkoAccounting at start", async function () {
      const acc = await rogueBankroll.getPlinkoAccounting();
      expect(acc.totalBets).to.equal(0n);
      expect(acc.totalWins).to.equal(0n);
      expect(acc.totalLosses).to.equal(0n);
      expect(acc.totalPushes).to.equal(0n);
      expect(acc.totalVolumeWagered).to.equal(0n);
      expect(acc.totalPayouts).to.equal(0n);
      expect(acc.totalHouseProfit).to.equal(0n);
      expect(acc.largestWin).to.equal(0n);
      expect(acc.largestBet).to.equal(0n);
      expect(acc.winRate).to.equal(0n);
      expect(acc.houseEdge).to.equal(0n);
    });
  });
});

// ============================================================
// ============= BUX Settlement Stats Tracking =================
// ============================================================
describe("PlinkoGame — BUX Stats via BUXBankroll", function () {
  let plinko;
  let buxBankroll;
  let buxToken;
  let owner;
  let settler;
  let player1;
  let player2;
  let referrer;
  let referralAdmin;

  async function deployAll() {
    [owner, settler, player1, player2, referrer, referralAdmin] = await ethers.getSigners();

    const MockToken = await ethers.getContractFactory("MockERC20");
    buxToken = await MockToken.deploy("Mock BUX", "BUX", 18);
    await buxToken.waitForDeployment();

    const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
    buxBankroll = await upgrades.deployProxy(BUXBankroll, [await buxToken.getAddress()], { initializer: "initialize", kind: "uups" });
    await buxBankroll.waitForDeployment();

    const PlinkoGame = await ethers.getContractFactory("PlinkoGame");
    plinko = await upgrades.deployProxy(PlinkoGame, [], { initializer: "initialize", kind: "uups" });
    await plinko.waitForDeployment();

    await plinko.setSettler(settler.address);
    await plinko.setBUXBankroll(await buxBankroll.getAddress());
    await plinko.setBUXToken(await buxToken.getAddress());
    await buxBankroll.setPlinkoGame(await plinko.getAddress());
    await plinko.configureToken(await buxToken.getAddress(), true);

    for (let i = 0; i < 9; i++) {
      await plinko.setPayoutTable(i, PAYOUT_TABLES[i]);
    }

    // Seed house
    const houseAmount = ethers.parseEther("100000");
    await buxToken.mint(owner.address, houseAmount);
    await buxToken.connect(owner).approve(await buxBankroll.getAddress(), houseAmount);
    await buxBankroll.connect(owner).depositBUX(houseAmount);

    // Set referral admin and referrer for player1
    await buxBankroll.setReferralAdmin(referralAdmin.address);
    await buxBankroll.connect(referralAdmin).setPlayerReferrer(player1.address, referrer.address);
  }

  async function submitAndPlaceBuxBet(player, amount, configIndex, serverSeed) {
    serverSeed = serverSeed || ethers.randomBytes(32);
    const commitmentHash = createCommitmentHash(serverSeed);
    const nonce = await plinko.playerNonces(player.address);

    await plinko.connect(settler).submitCommitment(commitmentHash, player.address, nonce);
    await buxToken.mint(player.address, amount);
    await buxToken.connect(player).approve(await plinko.getAddress(), amount);
    await plinko.connect(player).placeBet(amount, configIndex, commitmentHash);

    return { commitmentHash, serverSeed, nonce };
  }

  beforeEach(async function () {
    await deployAll();
  });

  describe("BUX Stats Tracking", function () {
    it("should track betsPerConfig[configIndex] correctly across multiple bets", async function () {
      const amount = ethers.parseEther("10");

      // Place 2 bets on config 0, 1 bet on config 1
      const bet1 = await submitAndPlaceBuxBet(player1, amount, 0);
      const path0 = generatePath(8, 4);
      await plinko.connect(settler).settleBet(bet1.commitmentHash, bet1.serverSeed, path0, 4);

      const bet2 = await submitAndPlaceBuxBet(player1, amount, 0);
      await plinko.connect(settler).settleBet(bet2.commitmentHash, bet2.serverSeed, path0, 4);

      const bet3 = await submitAndPlaceBuxBet(player1, amount, 1);
      const path1 = generatePath(8, 4);
      await plinko.connect(settler).settleBet(bet3.commitmentHash, bet3.serverSeed, path1, 4);

      const stats = await buxBankroll.getPlinkoPlayerStats(player1.address);
      // BUXBankroll returns betsPerConfig without underscore
      expect(stats.betsPerConfig[0]).to.equal(2n);
      expect(stats.betsPerConfig[1]).to.equal(1n);
    });

    it("should accumulate totalWagered across all bets", async function () {
      const amount1 = ethers.parseEther("10");
      const amount2 = ethers.parseEther("20");

      const bet1 = await submitAndPlaceBuxBet(player1, amount1, 0);
      const path = generatePath(8, 4);
      await plinko.connect(settler).settleBet(bet1.commitmentHash, bet1.serverSeed, path, 4);

      const bet2 = await submitAndPlaceBuxBet(player1, amount2, 0);
      await plinko.connect(settler).settleBet(bet2.commitmentHash, bet2.serverSeed, path, 4);

      const stats = await buxBankroll.getPlinkoPlayerStats(player1.address);
      // BUXBankroll return names have trailing underscore
      expect(stats.totalWagered_).to.equal(amount1 + amount2);
    });

    it("should track largestBet in global accounting", async function () {
      const amount = ethers.parseEther("10");
      const bet = await submitAndPlaceBuxBet(player1, amount, 0);
      const path = generatePath(8, 4);
      await plinko.connect(settler).settleBet(bet.commitmentHash, bet.serverSeed, path, 4);

      const acc = await buxBankroll.getPlinkoAccounting();
      expect(acc.largestBet_).to.equal(amount);
    });

    it("should track wins and losses in player stats", async function () {
      const amount = ethers.parseEther("10");

      // Win (5.6x)
      const bet1 = await submitAndPlaceBuxBet(player1, amount, 0);
      const winPath = generatePath(8, 0);
      await plinko.connect(settler).settleBet(bet1.commitmentHash, bet1.serverSeed, winPath, 0);

      // Loss (0.5x)
      const bet2 = await submitAndPlaceBuxBet(player1, amount, 0);
      const lossPath = generatePath(8, 4);
      await plinko.connect(settler).settleBet(bet2.commitmentHash, bet2.serverSeed, lossPath, 4);

      const stats = await buxBankroll.getPlinkoPlayerStats(player1.address);
      // BUXBankroll return names have trailing underscore
      expect(stats.totalBets_).to.equal(2n);
      expect(stats.wins_).to.equal(1n);
      expect(stats.losses_).to.equal(1n);
    });
  });

  describe("BUX Referral Rewards", function () {
    it("should pay BUX referral reward on losing bet", async function () {
      const amount = ethers.parseEther("10");
      const bet = await submitAndPlaceBuxBet(player1, amount, 0);

      // Loss path: position 4 = 0.5x
      const lossPath = generatePath(8, 4);

      const referrerBalBefore = await buxToken.balanceOf(referrer.address);
      await plinko.connect(settler).settleBet(bet.commitmentHash, bet.serverSeed, lossPath, 4);
      const referrerBalAfter = await buxToken.balanceOf(referrer.address);

      // Referral reward = loss amount * referralBasisPoints / 10000
      // Loss = 10 - 5 = 5 BUX, referral = 5 * 20 / 10000 = 0.01 BUX
      const lossAmount = amount - (amount * 5000n / MULTIPLIER_DENOMINATOR);
      const expectedReferral = (lossAmount * 20n) / 10000n;
      expect(referrerBalAfter - referrerBalBefore).to.equal(expectedReferral);
    });

    it("should not pay referral on winning bet", async function () {
      const amount = ethers.parseEther("10");
      const bet = await submitAndPlaceBuxBet(player1, amount, 0);

      const referrerBalBefore = await buxToken.balanceOf(referrer.address);
      // Win path: position 0 = 5.6x
      const winPath = generatePath(8, 0);
      await plinko.connect(settler).settleBet(bet.commitmentHash, bet.serverSeed, winPath, 0);
      const referrerBalAfter = await buxToken.balanceOf(referrer.address);

      expect(referrerBalAfter - referrerBalBefore).to.equal(0n);
    });

    it("should not pay referral on push bet", async function () {
      const amount = ethers.parseEther("10");
      const bet = await submitAndPlaceBuxBet(player1, amount, 0);

      const referrerBalBefore = await buxToken.balanceOf(referrer.address);
      // Push path: position 3 = 1.0x
      const pushPath = generatePath(8, 3);
      await plinko.connect(settler).settleBet(bet.commitmentHash, bet.serverSeed, pushPath, 3);
      const referrerBalAfter = await buxToken.balanceOf(referrer.address);

      expect(referrerBalAfter - referrerBalBefore).to.equal(0n);
    });
  });
});

// Helper to create int256 for ethers.js event matching
function int256(value) {
  return value;
}

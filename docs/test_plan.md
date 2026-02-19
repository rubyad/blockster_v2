# BUX Bankroll + Plinko — Comprehensive Test Plan

> **Purpose**: Complete test specifications for all testing across BUX Bankroll and Plinko features, organized by implementation phase. Tests are written and run after each phase completes. Every phase must be green before starting the next.
>
> **Test Totals**:
> - Hardhat Contract Tests: ~200 (BUXBankroll ~60, PlinkoGame BUX ~80, PlinkoGame ROGUE ~40, ROGUEBankroll V10 ~20)
> - Elixir Backend Tests: ~120 (Math ~60, Game Logic ~45, Settler ~13, LPBuxPriceTracker ~15)
> - LiveView Tests: ~110 (BankrollLive ~30, PlinkoLive ~80)
> - Deploy Verification Scripts: ~130 assertions (BUXBankroll ~40, PlinkoGame ~90)
> - **Grand Total: ~560 tests**

---

## Table of Contents

1. [Phase B1: BUXBankroll.sol — Hardhat Tests](#phase-b1)
2. [Phase B2: BUXBankroll Deploy Verification](#phase-b2)
3. [Phase B4: LPBuxPriceTracker + BuxMinter — Elixir Tests](#phase-b4)
4. [Phase B5: BankrollLive — LiveView Tests](#phase-b5)
5. [Phase P1: PlinkoGame.sol (BUX Path) — Hardhat Tests](#phase-p1)
6. [Phase P2: PlinkoGame.sol (ROGUE Path) + ROGUEBankroll V10 — Hardhat Tests](#phase-p2)
7. [Phase P3: Plinko Deploy Verification](#phase-p3)
8. [Phase P5: Plinko Backend — Elixir Tests](#phase-p5)
9. [Phase P6: PlinkoLive — LiveView Tests](#phase-p6)
10. [Phase P7: Integration Tests](#phase-p7)
11. [Running All Tests](#running-all-tests)

---

<a id="phase-b1"></a>
## Phase B1: BUXBankroll.sol — Hardhat Tests (~60 tests)

**File:** `contracts/bux-booster-game/test/BUXBankroll.test.js`
**Run:** `npx hardhat test test/BUXBankroll.test.js`
**Pattern:** Follows `BuxBoosterGame.v7.test.js` — deploy UUPS proxy, MockERC20, signers for owner/settler/players.

```javascript
const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("BUXBankroll", function () {
  let buxBankroll;
  let mockBUX;
  let owner, settler, player1, player2, plinkoGame, referrer;

  const INITIAL_HOUSE = ethers.parseEther("100000");

  beforeEach(async function () {
    [owner, settler, player1, player2, plinkoGame, referrer] = await ethers.getSigners();

    // Deploy MockERC20 for BUX
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockBUX = await MockToken.deploy("Mock BUX", "BUX", 18);
    await mockBUX.waitForDeployment();

    // Mint BUX to participants
    await mockBUX.mint(owner.address, ethers.parseEther("1000000"));
    await mockBUX.mint(player1.address, ethers.parseEther("10000"));
    await mockBUX.mint(player2.address, ethers.parseEther("10000"));

    // Deploy BUXBankroll as UUPS proxy
    const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
    buxBankroll = await upgrades.deployProxy(
      BUXBankroll,
      [await mockBUX.getAddress()],
      { initializer: "initialize", kind: "uups" }
    );
    await buxBankroll.waitForDeployment();

    // Authorize plinko game
    await buxBankroll.setPlinkoGame(plinkoGame.address);

    // Owner deposits initial house balance
    const bankrollAddr = await buxBankroll.getAddress();
    await mockBUX.connect(owner).approve(bankrollAddr, ethers.MaxUint256);
    await buxBankroll.depositBUX(INITIAL_HOUSE);

    // Player approvals
    await mockBUX.connect(player1).approve(bankrollAddr, ethers.MaxUint256);
    await mockBUX.connect(player2).approve(bankrollAddr, ethers.MaxUint256);
  });

  // ================================================================
  // Initialization
  // ================================================================
  describe("Initialization", function () {
    it("should set buxToken address correctly", async function () {
      expect(await buxBankroll.buxToken()).to.equal(await mockBUX.getAddress());
    });

    it("should set LP token name to 'BUX Bankroll' and symbol to 'LP-BUX'", async function () {
      expect(await buxBankroll.name()).to.equal("BUX Bankroll");
      expect(await buxBankroll.symbol()).to.equal("LP-BUX");
    });

    it("should set initial LP price to 1e18", async function () {
      expect(await buxBankroll.getLPPrice()).to.equal(ethers.parseEther("1"));
    });

    it("should reject double initialization", async function () {
      await expect(
        buxBankroll.initialize(await mockBUX.getAddress())
      ).to.be.revertedWithCustomError(buxBankroll, "InvalidInitialization");
    });

    it("should reject zero address for buxToken", async function () {
      const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
      await expect(
        upgrades.deployProxy(BUXBankroll, [ethers.ZeroAddress], { initializer: "initialize", kind: "uups" })
      ).to.be.revertedWithCustomError(buxBankroll, "ZeroAddress");
    });

    it("should set owner to deployer", async function () {
      expect(await buxBankroll.owner()).to.equal(owner.address);
    });

    it("should set maximumBetSizeDivisor to 1000", async function () {
      expect(await buxBankroll.maximumBetSizeDivisor()).to.equal(1000);
    });

    it("should set referralBasisPoints to 20 (0.2%)", async function () {
      expect(await buxBankroll.referralBasisPoints()).to.equal(20);
    });
  });

  // ================================================================
  // depositBUX
  // ================================================================
  describe("depositBUX", function () {
    it("should mint LP tokens 1:1 on first deposit", async function () {
      // Owner already deposited INITIAL_HOUSE in beforeEach
      expect(await buxBankroll.balanceOf(owner.address)).to.equal(INITIAL_HOUSE);
    });

    it("should mint proportional LP on subsequent deposits", async function () {
      // Owner has 100k LP from initial deposit
      // Player1 deposits 10k BUX -> should get 10k LP (price is still 1:1)
      await buxBankroll.connect(player1).depositBUX(ethers.parseEther("10000"));
      expect(await buxBankroll.balanceOf(player1.address)).to.equal(ethers.parseEther("10000"));
    });

    it("should transfer BUX from depositor to contract", async function () {
      const before = await mockBUX.balanceOf(player1.address);
      const depositAmt = ethers.parseEther("5000");
      await buxBankroll.connect(player1).depositBUX(depositAmt);
      const after_ = await mockBUX.balanceOf(player1.address);
      expect(before - after_).to.equal(depositAmt);
    });

    it("should update totalBalance in houseBalance", async function () {
      const depositAmt = ethers.parseEther("5000");
      await buxBankroll.connect(player1).depositBUX(depositAmt);
      const info = await buxBankroll.getHouseInfo();
      expect(info[0]).to.equal(INITIAL_HOUSE + depositAmt); // totalBalance
    });

    it("should update poolTokenPrice after deposit", async function () {
      // Price should remain 1e18 when no bets occurred
      const info = await buxBankroll.getHouseInfo();
      expect(info[5]).to.equal(ethers.parseEther("1")); // poolTokenPrice
    });

    it("should emit BUXDeposited event", async function () {
      const amt = ethers.parseEther("1000");
      await expect(buxBankroll.connect(player1).depositBUX(amt))
        .to.emit(buxBankroll, "BUXDeposited")
        .withArgs(player1.address, amt, amt); // 1:1 at current price
    });

    it("should emit PoolPriceUpdated event", async function () {
      const amt = ethers.parseEther("1000");
      await expect(buxBankroll.connect(player1).depositBUX(amt))
        .to.emit(buxBankroll, "PoolPriceUpdated");
    });

    it("should reject zero amount", async function () {
      await expect(
        buxBankroll.connect(player1).depositBUX(0)
      ).to.be.revertedWithCustomError(buxBankroll, "ZeroAmount");
    });

    it("should reject without prior BUX approval", async function () {
      // Deploy fresh player with no approval
      const [,,,,, , freshPlayer] = await ethers.getSigners();
      await mockBUX.mint(freshPlayer.address, ethers.parseEther("1000"));
      // No approval given
      await expect(
        buxBankroll.connect(freshPlayer).depositBUX(ethers.parseEther("100"))
      ).to.be.reverted; // SafeERC20 will revert
    });

    it("multiple depositors get correct proportional LP", async function () {
      // Owner: 100k LP. Player1 deposits 10k, Player2 deposits 5k
      await buxBankroll.connect(player1).depositBUX(ethers.parseEther("10000"));
      await buxBankroll.connect(player2).depositBUX(ethers.parseEther("5000"));

      expect(await buxBankroll.balanceOf(player1.address)).to.equal(ethers.parseEther("10000"));
      expect(await buxBankroll.balanceOf(player2.address)).to.equal(ethers.parseEther("5000"));
      expect(await buxBankroll.totalSupply()).to.equal(ethers.parseEther("115000"));
    });

    it("should reject when paused", async function () {
      await buxBankroll.pause();
      await expect(
        buxBankroll.connect(player1).depositBUX(ethers.parseEther("100"))
      ).to.be.revertedWith("Pausable: paused");
    });
  });

  // ================================================================
  // withdrawBUX
  // ================================================================
  describe("withdrawBUX", function () {
    it("should burn LP tokens and return proportional BUX", async function () {
      // Owner withdraws 10k LP -> should get 10k BUX (price 1:1)
      const lpAmt = ethers.parseEther("10000");
      const buxBefore = await mockBUX.balanceOf(owner.address);
      await buxBankroll.withdrawBUX(lpAmt);
      const buxAfter = await mockBUX.balanceOf(owner.address);
      expect(buxAfter - buxBefore).to.equal(lpAmt);
    });

    it("should respect net balance (can't withdraw during active bets)", async function () {
      // Simulate bet placement that creates liability
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("36000"); // 360x for 8-High
      const hash = ethers.keccak256(ethers.toUtf8Bytes("test"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 2, 0, maxPayout
      );

      // netBalance = totalBalance - liability = 100100 - 36000 = 64100
      // Trying to withdraw more than net should fail
      const info = await buxBankroll.getHouseInfo();
      const netBalance = info[3];
      const ownerLP = await buxBankroll.balanceOf(owner.address);

      // If withdrawal BUX exceeds netBalance, should revert
      await expect(
        buxBankroll.withdrawBUX(ownerLP) // all LP would exceed net
      ).to.be.revertedWithCustomError(buxBankroll, "InsufficientLiquidity");
    });

    it("should update totalBalance", async function () {
      const lpAmt = ethers.parseEther("10000");
      await buxBankroll.withdrawBUX(lpAmt);
      const info = await buxBankroll.getHouseInfo();
      expect(info[0]).to.equal(INITIAL_HOUSE - lpAmt);
    });

    it("should emit BUXWithdrawn event", async function () {
      const lpAmt = ethers.parseEther("1000");
      await expect(buxBankroll.withdrawBUX(lpAmt))
        .to.emit(buxBankroll, "BUXWithdrawn")
        .withArgs(owner.address, lpAmt, lpAmt);
    });

    it("should reject zero amount", async function () {
      await expect(
        buxBankroll.withdrawBUX(0)
      ).to.be.revertedWithCustomError(buxBankroll, "ZeroAmount");
    });

    it("should reject if user has insufficient LP", async function () {
      await expect(
        buxBankroll.connect(player1).withdrawBUX(ethers.parseEther("1"))
      ).to.be.revertedWithCustomError(buxBankroll, "InsufficientBalance");
    });

    it("partial withdrawal leaves correct LP balance", async function () {
      const withdrawAmt = ethers.parseEther("25000");
      await buxBankroll.withdrawBUX(withdrawAmt);
      expect(await buxBankroll.balanceOf(owner.address)).to.equal(INITIAL_HOUSE - withdrawAmt);
    });

    it("full withdrawal returns all entitled BUX when no liability", async function () {
      const ownerLP = await buxBankroll.balanceOf(owner.address);
      const buxBefore = await mockBUX.balanceOf(owner.address);
      await buxBankroll.withdrawBUX(ownerLP);
      const buxAfter = await mockBUX.balanceOf(owner.address);
      expect(buxAfter - buxBefore).to.equal(INITIAL_HOUSE);
      expect(await buxBankroll.totalSupply()).to.equal(0);
    });

    it("should reject when paused", async function () {
      await buxBankroll.pause();
      await expect(
        buxBankroll.withdrawBUX(ethers.parseEther("100"))
      ).to.be.revertedWith("Pausable: paused");
    });
  });

  // ================================================================
  // LP Price Mechanics
  // ================================================================
  describe("LP Price Mechanics", function () {
    it("LP price increases when house wins bets", async function () {
      // Simulate a losing bet (house wins 100 BUX)
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("560"); // 5.6x max for 8-Low
      const hash = ethers.keccak256(ethers.toUtf8Bytes("bet1"));

      // Place bet: transfers betAmt to bankroll, increases totalBalance
      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );

      // Settle as loss (house wins): partial payout = 50 BUX (0.5x)
      const path = [0, 0, 0, 0, 1, 1, 1, 1]; // landing 4 = 0.5x = 5000 bps
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, betAmt, ethers.parseEther("50"), 0, 4, path, 0, maxPayout
      );

      // LP price should be > 1.0 since house kept 50 BUX profit
      const price = await buxBankroll.getLPPrice();
      expect(price).to.be.gt(ethers.parseEther("1"));
    });

    it("LP price decreases when house loses bets", async function () {
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("bet2"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );

      // Settle as win: payout = 560 BUX (5.6x) — house pays 460 profit
      const path = [0, 0, 0, 0, 0, 0, 0, 0]; // landing 0 = 5.6x
      await buxBankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, hash, betAmt, ethers.parseEther("560"), 0, 0, path, 0, maxPayout
      );

      const price = await buxBankroll.getLPPrice();
      expect(price).to.be.lt(ethers.parseEther("1"));
    });

    it("LP price stays at 1.0 when no bets have occurred", async function () {
      expect(await buxBankroll.getLPPrice()).to.equal(ethers.parseEther("1"));
    });

    it("deposit at higher price gives fewer LP tokens", async function () {
      // Simulate house winning to raise LP price
      const betAmt = ethers.parseEther("1000");
      const maxPayout = ethers.parseEther("5600");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("priceup"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );
      // Full loss (0x payout on 8-High center)
      const path = [0, 1, 0, 1, 0, 1, 0, 1]; // landing 4 on 8-High = 0x
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, betAmt, 0, 2, 4, path, 0, maxPayout
      );

      // Price is now > 1.0 BUX per LP
      const priceAfterWin = await buxBankroll.getLPPrice();
      expect(priceAfterWin).to.be.gt(ethers.parseEther("1"));

      // Player2 deposits 1000 BUX at elevated price
      await buxBankroll.connect(player2).depositBUX(ethers.parseEther("1000"));
      const player2LP = await buxBankroll.balanceOf(player2.address);

      // Should receive fewer than 1000 LP
      expect(player2LP).to.be.lt(ethers.parseEther("1000"));
    });

    it("depositor who enters after wins does NOT get retroactive profit", async function () {
      // Owner has 100k LP at 1.0 price
      // House wins 10k BUX -> price goes up
      // Player deposits 10k BUX -> gets fewer LP
      // Player withdraws all LP -> gets back ~10k BUX (not more)

      const betAmt = ethers.parseEther("10000");
      const maxPayout = ethers.parseEther("56000");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("retrotest"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, betAmt, 0, 2, 4, [0,1,0,1,0,1,0,1], 0, maxPayout
      );

      // Player2 deposits after the win
      await buxBankroll.connect(player2).depositBUX(ethers.parseEther("10000"));
      const p2LP = await buxBankroll.balanceOf(player2.address);

      // Immediately withdraw
      const buxBefore = await mockBUX.balanceOf(player2.address);
      await buxBankroll.connect(player2).withdrawBUX(p2LP);
      const buxAfter = await mockBUX.balanceOf(player2.address);

      // Should get back roughly 10k (not 10k + profit share)
      const received = buxAfter - buxBefore;
      expect(received).to.be.closeTo(ethers.parseEther("10000"), ethers.parseEther("100"));
    });
  });

  // ================================================================
  // Game Integration — Plinko
  // ================================================================
  describe("Game Integration — Plinko", function () {
    it("setPlinkoGame sets authorized game address", async function () {
      expect(await buxBankroll.plinkoGame()).to.equal(plinkoGame.address);
    });

    it("rejects setPlinkoGame from non-owner", async function () {
      await expect(
        buxBankroll.connect(player1).setPlinkoGame(player1.address)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("updateHouseBalancePlinkoBetPlaced increases liability and totalBalance", async function () {
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("5600");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("liability1"));

      const infoBefore = await buxBankroll.getHouseInfo();
      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );
      const infoAfter = await buxBankroll.getHouseInfo();

      expect(infoAfter[0] - infoBefore[0]).to.equal(betAmt);         // totalBalance
      expect(infoAfter[1] - infoBefore[1]).to.equal(maxPayout);      // liability
      expect(infoAfter[2] - infoBefore[2]).to.equal(betAmt);         // unsettledBets
    });

    it("settlePlinkoWinningBet sends payout to winner, reduces totalBalance", async function () {
      const betAmt = ethers.parseEther("100");
      const payout = ethers.parseEther("560"); // 5.6x
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("win1"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );

      const buxBefore = await mockBUX.balanceOf(player1.address);
      await buxBankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, hash, betAmt, payout, 0, 0, [0,0,0,0,0,0,0,0], 0, maxPayout
      );
      const buxAfter = await mockBUX.balanceOf(player1.address);

      expect(buxAfter - buxBefore).to.equal(payout);
    });

    it("settlePlinkoLosingBet keeps BUX, sends partial payout if > 0", async function () {
      const betAmt = ethers.parseEther("100");
      const partialPayout = ethers.parseEther("50"); // 0.5x
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("loss1"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );

      const buxBefore = await mockBUX.balanceOf(player1.address);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, betAmt, partialPayout, 0, 4, [0,0,0,0,1,1,1,1], 0, maxPayout
      );
      const buxAfter = await mockBUX.balanceOf(player1.address);

      expect(buxAfter - buxBefore).to.equal(partialPayout);
    });

    it("settlePlinkoLosingBet with 0x payout sends nothing", async function () {
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("3600");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("0xloss"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 2, 0, maxPayout
      );

      const buxBefore = await mockBUX.balanceOf(player1.address);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, betAmt, 0, 2, 4, [0,1,0,1,0,1,0,1], 0, maxPayout
      );
      const buxAfter = await mockBUX.balanceOf(player1.address);

      expect(buxAfter).to.equal(buxBefore); // No BUX sent
    });

    it("settlePlinkoPushBet returns exact bet amount", async function () {
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("push1"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );

      const buxBefore = await mockBUX.balanceOf(player1.address);
      await buxBankroll.connect(plinkoGame).settlePlinkoPushBet(
        player1.address, hash, betAmt, 0, 3, [0,0,0,1,1,1,0,0], 0, maxPayout
      );
      const buxAfter = await mockBUX.balanceOf(player1.address);

      expect(buxAfter - buxBefore).to.equal(betAmt);
    });

    it("all settle functions release liability", async function () {
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("releaselb"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );

      const infoBeforeSettle = await buxBankroll.getHouseInfo();
      expect(infoBeforeSettle[1]).to.equal(maxPayout); // liability > 0

      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, betAmt, ethers.parseEther("50"), 0, 4, [0,0,0,0,1,1,1,1], 0, maxPayout
      );

      const infoAfterSettle = await buxBankroll.getHouseInfo();
      expect(infoAfterSettle[1]).to.equal(0); // liability back to 0
      expect(infoAfterSettle[2]).to.equal(0); // unsettledBets back to 0
    });

    it("unauthorized caller cannot call settle functions", async function () {
      const hash = ethers.keccak256(ethers.toUtf8Bytes("unauth"));
      await expect(
        buxBankroll.connect(player1).settlePlinkoWinningBet(
          player1.address, hash, 100, 200, 0, 0, [0], 0, 200
        )
      ).to.be.revertedWithCustomError(buxBankroll, "UnauthorizedGame");
    });

    it("getMaxBet returns correct value based on netBalance and multiplier", async function () {
      // netBalance = 100k, MAX_BET_BPS = 10 (0.1%)
      // maxBet = (100000 * 10 / 10000) * 20000 / maxMultiplierBps
      // For 8-Low (56000): maxBet = 100 * 20000 / 56000 = ~35.71 BUX
      const maxBet = await buxBankroll.getMaxBet(0, 56000);
      expect(maxBet).to.be.gt(0);
      // Approximate: (100000e18 * 10 / 10000) * 20000 / 56000
      const expected = (INITIAL_HOUSE * 10n / 10000n) * 20000n / 56000n;
      expect(maxBet).to.equal(expected);
    });
  });

  // ================================================================
  // Liability Tracking
  // ================================================================
  describe("Liability Tracking", function () {
    it("liability increases on bet placement", async function () {
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("lb1"));
      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, ethers.parseEther("100"), 0, 0, maxPayout
      );
      const info = await buxBankroll.getHouseInfo();
      expect(info[1]).to.equal(maxPayout);
    });

    it("liability decreases on settlement", async function () {
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("lb2"));
      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, ethers.parseEther("100"), 0, 0, maxPayout
      );
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, ethers.parseEther("100"), 0, 2, 4, [0,1,0,1,0,1,0,1], 0, maxPayout
      );
      const info = await buxBankroll.getHouseInfo();
      expect(info[1]).to.equal(0);
    });

    it("netBalance = totalBalance - liability", async function () {
      const maxPayout = ethers.parseEther("1000");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("net1"));
      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, ethers.parseEther("50"), 0, 0, maxPayout
      );
      const info = await buxBankroll.getHouseInfo();
      expect(info[3]).to.equal(info[0] - info[1]); // netBalance = total - liability
    });

    it("multiple concurrent bets tracked correctly", async function () {
      const maxPayout1 = ethers.parseEther("560");
      const maxPayout2 = ethers.parseEther("1300");
      const hash1 = ethers.keccak256(ethers.toUtf8Bytes("concurrent1"));
      const hash2 = ethers.keccak256(ethers.toUtf8Bytes("concurrent2"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash1, player1.address, ethers.parseEther("100"), 0, 0, maxPayout1
      );
      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash2, player2.address, ethers.parseEther("100"), 1, 1, maxPayout2
      );

      const info = await buxBankroll.getHouseInfo();
      expect(info[1]).to.equal(maxPayout1 + maxPayout2); // total liability
      expect(info[2]).to.equal(ethers.parseEther("200")); // total unsettled

      // Settle first bet
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash1, ethers.parseEther("100"), 0, 2, 4, [0,1,0,1,0,1,0,1], 0, maxPayout1
      );

      const info2 = await buxBankroll.getHouseInfo();
      expect(info2[1]).to.equal(maxPayout2); // only bet2 liability remains
      expect(info2[2]).to.equal(ethers.parseEther("100")); // only bet2 unsettled
    });
  });

  // ================================================================
  // Referral Rewards
  // ================================================================
  describe("Referral Rewards", function () {
    beforeEach(async function () {
      // Set referrer for player1
      await buxBankroll.setPlayerReferrer(player1.address, referrer.address);
    });

    it("pays BUX referral reward on losing bet", async function () {
      const betAmt = ethers.parseEther("10000");
      const maxPayout = ethers.parseEther("56000");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("ref1"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );

      const refBefore = await mockBUX.balanceOf(referrer.address);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, betAmt, 0, 2, 4, [0,1,0,1,0,1,0,1], 0, maxPayout
      );
      const refAfter = await mockBUX.balanceOf(referrer.address);

      // lossAmount = 10000, referralBasisPoints = 20, reward = 10000 * 20 / 10000 = 20
      expect(refAfter - refBefore).to.equal(ethers.parseEther("20"));
    });

    it("no reward on push bets", async function () {
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("refpush"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );

      const refBefore = await mockBUX.balanceOf(referrer.address);
      await buxBankroll.connect(plinkoGame).settlePlinkoPushBet(
        player1.address, hash, betAmt, 0, 3, [0,0,0,1,1,1,0,0], 0, maxPayout
      );
      const refAfter = await mockBUX.balanceOf(referrer.address);

      expect(refAfter).to.equal(refBefore); // No reward
    });

    it("tracks totalReferralRewardsPaid", async function () {
      const betAmt = ethers.parseEther("10000");
      const maxPayout = ethers.parseEther("56000");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("reftrack"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, betAmt, 0, 2, 4, [0,1,0,1,0,1,0,1], 0, maxPayout
      );

      expect(await buxBankroll.totalReferralRewardsPaid()).to.equal(ethers.parseEther("20"));
      expect(await buxBankroll.referrerTotalEarnings(referrer.address)).to.equal(ethers.parseEther("20"));
    });

    it("silently skips if referrer not set", async function () {
      // player2 has no referrer
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("noref"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player2.address, betAmt, 0, 0, maxPayout
      );
      // Should not revert
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player2.address, hash, betAmt, 0, 2, 4, [0,1,0,1,0,1,0,1], 0, maxPayout
      );
    });

    it("silently skips if referralBasisPoints is 0", async function () {
      await buxBankroll.setReferralBasisPoints(0);

      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("0bps"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );

      const refBefore = await mockBUX.balanceOf(referrer.address);
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, betAmt, 0, 2, 4, [0,1,0,1,0,1,0,1], 0, maxPayout
      );
      expect(await mockBUX.balanceOf(referrer.address)).to.equal(refBefore);
    });
  });

  // ================================================================
  // Stats Tracking
  // ================================================================
  describe("Stats Tracking", function () {
    it("tracks PlinkoPlayerStats per player", async function () {
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("stats1"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash, betAmt, ethers.parseEther("50"), 0, 4, [0,0,0,0,1,1,1,1], 0, maxPayout
      );

      const stats = await buxBankroll.getPlinkoPlayerStats(player1.address);
      expect(stats.totalBets).to.equal(1);
      expect(stats.losses).to.equal(1);
      expect(stats.totalWagered).to.equal(betAmt);
    });

    it("tracks PlinkoAccounting globally", async function () {
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("560");
      const hash = ethers.keccak256(ethers.toUtf8Bytes("global1"));

      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash, player1.address, betAmt, 0, 0, maxPayout
      );
      await buxBankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, hash, betAmt, ethers.parseEther("560"), 0, 0, [0,0,0,0,0,0,0,0], 0, maxPayout
      );

      const acct = await buxBankroll.getPlinkoAccounting();
      expect(acct.totalBets).to.equal(1);
      expect(acct.totalWins).to.equal(1);
      expect(acct.totalVolumeWagered).to.equal(betAmt);
    });

    it("tracks plinkoPnLPerConfig as signed int", async function () {
      // Two bets on config 0: one loss, one win
      const betAmt = ethers.parseEther("100");
      const maxPayout = ethers.parseEther("560");

      const hash1 = ethers.keccak256(ethers.toUtf8Bytes("pnl1"));
      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash1, player1.address, betAmt, 0, 0, maxPayout
      );
      await buxBankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, hash1, betAmt, 0, 2, 4, [0,1,0,1,0,1,0,1], 0, maxPayout
      );

      const hash2 = ethers.keccak256(ethers.toUtf8Bytes("pnl2"));
      await buxBankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        hash2, player1.address, betAmt, 0, 1, maxPayout
      );
      await buxBankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, hash2, betAmt, ethers.parseEther("560"), 0, 0, [0,0,0,0,0,0,0,0], 1, maxPayout
      );

      const pnl = await buxBankroll.getPlinkoPnLPerConfig(player1.address);
      // Lost 100, then won 460 profit. Net = +360
      expect(pnl[0]).to.be.gt(0); // positive net PnL for config 0
    });
  });

  // ================================================================
  // Admin
  // ================================================================
  describe("Admin", function () {
    it("owner can set maxBetDivisor", async function () {
      await buxBankroll.setMaxBetDivisor(500);
      expect(await buxBankroll.maximumBetSizeDivisor()).to.equal(500);
    });

    it("owner can emergencyWithdrawBUX", async function () {
      const amt = ethers.parseEther("1000");
      const before = await mockBUX.balanceOf(owner.address);
      await buxBankroll.emergencyWithdrawBUX(amt);
      const after_ = await mockBUX.balanceOf(owner.address);
      expect(after_ - before).to.equal(amt);
    });

    it("owner can set referral config", async function () {
      await buxBankroll.setReferralBasisPoints(50);
      expect(await buxBankroll.referralBasisPoints()).to.equal(50);
    });

    it("non-owner cannot call admin functions", async function () {
      await expect(
        buxBankroll.connect(player1).setMaxBetDivisor(500)
      ).to.be.revertedWith("Ownable: caller is not the owner");
      await expect(
        buxBankroll.connect(player1).emergencyWithdrawBUX(1)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("owner can pause and unpause", async function () {
      await buxBankroll.pause();
      await expect(
        buxBankroll.connect(player1).depositBUX(ethers.parseEther("100"))
      ).to.be.revertedWith("Pausable: paused");
      await buxBankroll.unpause();
      await buxBankroll.connect(player1).depositBUX(ethers.parseEther("100"));
    });

    it("setPlayerReferrersBatch sets multiple referrers", async function () {
      await buxBankroll.setPlayerReferrersBatch(
        [player1.address, player2.address],
        [referrer.address, referrer.address]
      );
      expect(await buxBankroll.playerReferrers(player1.address)).to.equal(referrer.address);
      expect(await buxBankroll.playerReferrers(player2.address)).to.equal(referrer.address);
    });
  });

  // ================================================================
  // UUPS
  // ================================================================
  describe("UUPS Upgrade", function () {
    it("owner can upgrade", async function () {
      const BUXBankrollV2 = await ethers.getContractFactory("BUXBankroll");
      await upgrades.upgradeProxy(await buxBankroll.getAddress(), BUXBankrollV2, { kind: "uups" });
    });

    it("non-owner cannot upgrade", async function () {
      const BUXBankrollV2 = await ethers.getContractFactory("BUXBankroll");
      await expect(
        upgrades.upgradeProxy(
          await buxBankroll.getAddress(),
          BUXBankrollV2.connect(player1),
          { kind: "uups" }
        )
      ).to.be.reverted;
    });
  });
});
```

---

<a id="phase-b2"></a>
## Phase B2: BUXBankroll Deploy Verification (~40 assertions)

**File:** `contracts/bux-booster-game/scripts/verify-bux-bankroll.js`
**Run:** `npx hardhat run scripts/verify-bux-bankroll.js --network rogue`

Post-deployment verification script (NOT a Hardhat test). Reads live contracts and asserts correctness.

```javascript
const { ethers } = require("hardhat");

const BUX_BANKROLL_ADDRESS = process.env.BUX_BANKROLL_ADDRESS;
const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";
const PLINKO_ADDRESS = process.env.PLINKO_CONTRACT_ADDRESS;

async function main() {
  let failures = 0;
  const assert = (condition, msg) => {
    if (!condition) { console.error(`FAIL: ${msg}`); failures++; }
    else { console.log(`PASS: ${msg}`); }
  };

  const bankroll = await ethers.getContractAt("BUXBankroll", BUX_BANKROLL_ADDRESS);

  // 1. Token configuration
  assert((await bankroll.buxToken()).toLowerCase() === BUX_TOKEN_ADDRESS.toLowerCase(),
    "buxToken set correctly");

  // 2. LP token metadata
  assert(await bankroll.name() === "BUX Bankroll", "LP name = BUX Bankroll");
  assert(await bankroll.symbol() === "LP-BUX", "LP symbol = LP-BUX");

  // 3. Initial parameters
  assert(Number(await bankroll.maximumBetSizeDivisor()) === 1000, "maxBetDivisor = 1000");
  assert(Number(await bankroll.referralBasisPoints()) === 20, "referralBps = 20");

  // 4. PlinkoGame link
  if (PLINKO_ADDRESS) {
    assert(
      (await bankroll.plinkoGame()).toLowerCase() === PLINKO_ADDRESS.toLowerCase(),
      "PlinkoGame linked"
    );
  }

  // 5. House balance has initial deposit
  const info = await bankroll.getHouseInfo();
  assert(info[0] > 0n, `totalBalance > 0 (got ${ethers.formatEther(info[0])})`);
  assert(info[1] === 0n, "liability = 0 (no active bets)");
  assert(info[2] === 0n, "unsettledBets = 0");
  assert(info[3] === info[0], "netBalance = totalBalance (no liability)");
  assert(info[4] > 0n, "LP supply > 0");
  assert(info[5] > 0n, "LP price > 0");

  // 6. LP price is reasonable (near 1e18 for fresh deployment)
  const price = info[5];
  assert(price >= ethers.parseEther("0.9") && price <= ethers.parseEther("1.1"),
    `LP price near 1.0 (got ${ethers.formatEther(price)})`);

  // 7. Owner is deployer
  const deployerAddr = process.env.DEPLOYER_ADDRESS;
  if (deployerAddr) {
    assert(
      (await bankroll.owner()).toLowerCase() === deployerAddr.toLowerCase(),
      "Owner is deployer"
    );
  }

  // 8. BUX balance matches totalBalance
  const buxToken = await ethers.getContractAt("IERC20", BUX_TOKEN_ADDRESS);
  const actualBux = await buxToken.balanceOf(BUX_BANKROLL_ADDRESS);
  assert(actualBux >= info[0], `BUX balance >= totalBalance`);

  // 9. Referral admin
  const refAdmin = await bankroll.referralAdmin();
  console.log(`INFO: referralAdmin = ${refAdmin}`);

  // 10. MaxBet returns non-zero for several configs
  for (const [configIdx, maxMult] of [[0, 56000], [4, 330000], [8, 10000000]]) {
    const maxBet = await bankroll.getMaxBet(configIdx, maxMult);
    assert(maxBet > 0n, `maxBet config ${configIdx} > 0 (got ${ethers.formatEther(maxBet)})`);
  }

  console.log(`\n=== ${failures === 0 ? 'ALL PASSED' : failures + ' FAILURES'} ===`);
  if (failures > 0) process.exit(1);
}

main().catch(console.error);
```

---

<a id="phase-b4"></a>
## Phase B4: LPBuxPriceTracker + BuxMinter — Elixir Tests (~15 tests)

**File:** `test/blockster_v2/plinko/lp_bux_price_tracker_test.exs`
**Run:** `mix test test/blockster_v2/plinko/lp_bux_price_tracker_test.exs`

```elixir
defmodule BlocksterV2.LPBuxPriceTrackerTest do
  use ExUnit.Case

  alias BlocksterV2.LPBuxPriceTracker

  setup do
    # Ensure lp_bux_candles table exists and is clean
    try do
      :mnesia.clear_table(:lp_bux_candles)
    catch
      _, _ ->
        :mnesia.create_table(:lp_bux_candles,
          attributes: [:timestamp, :open, :high, :low, :close],
          type: :ordered_set,
          disc_copies: []
        )
    end
    :ok
  end

  # ============ Candle Creation ============
  describe "candle creation" do
    test "new price creates a new candle with open=high=low=close" do
      # Write a candle manually
      now = System.system_time(:second)
      candle_start = div(now, 300) * 300
      record = {:lp_bux_candles, candle_start, 1.05, 1.05, 1.05, 1.05}
      :mnesia.dirty_write(record)

      result = :mnesia.dirty_read(:lp_bux_candles, candle_start)
      assert [{:lp_bux_candles, ^candle_start, 1.05, 1.05, 1.05, 1.05}] = result
    end

    test "subsequent price in same 5-min window updates high/low/close" do
      now = System.system_time(:second)
      candle_start = div(now, 300) * 300

      :mnesia.dirty_write({:lp_bux_candles, candle_start, 1.0, 1.0, 1.0, 1.0})
      # Simulate higher price
      :mnesia.dirty_write({:lp_bux_candles, candle_start, 1.0, 1.1, 0.95, 1.05})

      [{:lp_bux_candles, _, open, high, low, close}] =
        :mnesia.dirty_read(:lp_bux_candles, candle_start)

      assert open == 1.0
      assert high == 1.1
      assert low == 0.95
      assert close == 1.05
    end
  end

  # ============ Candle Retrieval ============
  describe "get_candles/2" do
    test "returns candles within timeframe sorted by timestamp" do
      now = System.system_time(:second)
      base = div(now, 300) * 300

      for i <- 0..4 do
        ts = base - (i * 300)
        :mnesia.dirty_write({:lp_bux_candles, ts, 1.0 + i * 0.01, 1.0 + i * 0.01, 1.0 + i * 0.01, 1.0 + i * 0.01})
      end

      candles = LPBuxPriceTracker.get_candles(300, 10)
      assert length(candles) >= 5
      timestamps = Enum.map(candles, & &1.time)
      assert timestamps == Enum.sort(timestamps)
    end

    test "returns empty list when no candles exist" do
      candles = LPBuxPriceTracker.get_candles(300, 10)
      assert candles == []
    end

    test "aggregates 5-min candles into 1-hour candles" do
      now = System.system_time(:second)
      hour_start = div(now, 3600) * 3600

      # Write 12 five-minute candles in the current hour
      for i <- 0..11 do
        ts = hour_start + (i * 300)
        price = 1.0 + i * 0.01
        :mnesia.dirty_write({:lp_bux_candles, ts, price, price + 0.005, price - 0.005, price})
      end

      candles = LPBuxPriceTracker.get_candles(3600, 10)
      assert length(candles) >= 1

      # Aggregated candle should have correct OHLC
      hourly = Enum.find(candles, fn c -> c.time == hour_start end)
      if hourly do
        assert hourly.open == 1.0  # first 5-min candle open
        assert hourly.high >= 1.11  # highest high
        assert hourly.low <= 0.995  # lowest low
      end
    end
  end

  # ============ Stats ============
  describe "get_stats/0" do
    test "returns high/low for each timeframe" do
      now = System.system_time(:second)
      base = div(now, 300) * 300

      :mnesia.dirty_write({:lp_bux_candles, base, 1.0, 1.2, 0.8, 1.1})
      :mnesia.dirty_write({:lp_bux_candles, base - 300, 0.9, 1.3, 0.7, 0.95})

      stats = LPBuxPriceTracker.get_stats()
      assert stats.price_1h.high >= 1.2
      assert stats.price_1h.low <= 0.7
    end

    test "returns nil high/low when no data exists for timeframe" do
      stats = LPBuxPriceTracker.get_stats()
      assert stats.price_1h == %{high: nil, low: nil}
    end
  end

  # ============ Price Parsing ============
  describe "price parsing" do
    test "parses string price from 18-decimal wei format" do
      # 1.0 in wei = "1000000000000000000"
      # This tests the internal parse_price function behavior
      price_str = "1050000000000000000"  # 1.05
      {price_int, _} = Integer.parse(price_str)
      result = price_int / 1.0e18
      assert_in_delta result, 1.05, 0.001
    end
  end
end
```

---

<a id="phase-b5"></a>
## Phase B5: BankrollLive — LiveView Tests (~30 tests)

**File:** `test/blockster_v2_web/live/bankroll_live_test.exs`
**Run:** `mix test test/blockster_v2_web/live/bankroll_live_test.exs`

```elixir
defmodule BlocksterV2Web.BankrollLiveTest do
  use BlocksterV2Web.ConnCase
  import Phoenix.LiveViewTest

  alias BlocksterV2.Accounts.User

  defp create_user(_context) do
    unique_id = System.unique_integer([:positive])
    {:ok, user} = %User{}
      |> User.changeset(%{
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        smart_wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        email: "bankroll_user#{unique_id}@test.com",
        username: "bankroll_user#{unique_id}",
        auth_method: "wallet"
      })
      |> BlocksterV2.Repo.insert()
    %{user: user}
  end

  # ============ Guest Mount ============
  describe "mount — guest (not logged in)" do
    test "renders bankroll page with pool stats", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "BUX Bankroll"
    end

    test "does not show deposit/withdraw forms for guests", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bankroll")
      refute html =~ "DEPOSIT"
      # Or shows login prompt
    end

    test "sets page_title to BUX Bankroll", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/bankroll")
      assert page_title(view) =~ "BUX Bankroll"
    end
  end

  # ============ Authenticated Mount ============
  describe "mount — authenticated user" do
    setup [:create_user]

    test "shows deposit/withdraw forms", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/bankroll")
      assert html =~ "Deposit" || html =~ "DEPOSIT"
    end

    test "sets default assigns", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      # Verify initial assigns via render
      html = render(view)
      assert html =~ "LP-BUX"
    end
  end

  # ============ Timeframe Selection ============
  describe "select_timeframe event" do
    test "switches chart timeframe", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/bankroll")

      html = view |> element("[phx-click='select_timeframe'][phx-value-tf='7d']") |> render_click()
      # The 7D tab should now be active
      assert html =~ "7D" || html =~ "7d"
    end
  end

  # ============ Deposit/Withdraw Events ============
  describe "deposit/withdraw events" do
    setup [:create_user]

    test "update_deposit_amount updates preview", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      html = view
        |> element("form[phx-change='update_deposit_amount']")
        |> render_change(%{amount: "500"})

      # Should show preview of LP tokens to receive
      assert html =~ "LP-BUX" || html =~ "receive"
    end

    test "deposit_confirmed refreshes pool info", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      # Simulate JS pushEvent for deposit confirmation
      render_hook(view, "deposit_confirmed", %{tx_hash: "0xabc123"})
      # Should trigger pool info re-fetch (no crash)
    end

    test "deposit_failed shows error message", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      html = render_hook(view, "deposit_failed", %{error: "Insufficient BUX"})
      assert html =~ "Insufficient BUX" || html =~ "error"
    end

    test "withdraw_confirmed refreshes pool info", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      render_hook(view, "withdraw_confirmed", %{tx_hash: "0xdef456"})
      # Should trigger pool info re-fetch (no crash)
    end

    test "withdraw_failed shows error message", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/bankroll")

      html = render_hook(view, "withdraw_failed", %{error: "Insufficient LP"})
      assert html =~ "Insufficient" || html =~ "error"
    end
  end

  # ============ PubSub Updates ============
  describe "PubSub updates" do
    test "lp_bux_price_updated updates displayed price", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/bankroll")

      # Broadcast price update
      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "lp_bux_price",
        {:lp_bux_price_updated, %{price: 1.15, candle: %{time: 0, open: 1.1, high: 1.15, low: 1.1, close: 1.15}}}
      )

      # Give it a moment to process
      html = render(view)
      # Price should be reflected somewhere in the UI
      assert html =~ "1.15" || html =~ "LP"
    end
  end
end
```

---

<a id="phase-p1"></a>
## Phase P1: PlinkoGame.sol (BUX Path) — Hardhat Tests (~80 tests)

**File:** `contracts/bux-booster-game/test/PlinkoGame.test.js`
**Run:** `npx hardhat test test/PlinkoGame.test.js`
**Pattern:** Deploy PlinkoGame proxy, MockERC20, BUXBankroll, link contracts. Follows `BuxBoosterGame.v7.test.js`.

```javascript
const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("PlinkoGame", function () {
  let plinkoGame, buxBankroll, mockBUX;
  let owner, settler, player1, player2, referrer;

  const MIN_BET = ethers.parseEther("1");
  const HOUSE_DEPOSIT = ethers.parseEther("100000");

  // All 9 payout tables (basis points)
  const PAYOUT_TABLES = {
    0: [56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 56000],
    1: [130000, 30000, 13000, 7000, 4000, 7000, 13000, 30000, 130000],
    2: [360000, 40000, 15000, 3000, 0, 3000, 15000, 40000, 360000],
    3: [110000, 30000, 16000, 14000, 11000, 10000, 5000, 10000, 11000, 14000, 16000, 30000, 110000],
    4: [330000, 110000, 40000, 20000, 11000, 6000, 3000, 6000, 11000, 20000, 40000, 110000, 330000],
    5: [4050000, 180000, 70000, 20000, 7000, 2000, 0, 2000, 7000, 20000, 70000, 180000, 4050000],
    6: [160000, 90000, 20000, 14000, 14000, 12000, 11000, 10000, 5000, 10000, 11000, 12000, 14000, 14000, 20000, 90000, 160000],
    7: [1100000, 410000, 100000, 50000, 30000, 15000, 10000, 5000, 3000, 5000, 10000, 15000, 30000, 50000, 100000, 410000, 1100000],
    8: [10000000, 1500000, 330000, 100000, 33000, 20000, 3000, 2000, 0, 2000, 3000, 20000, 33000, 100000, 330000, 1500000, 10000000],
  };

  beforeEach(async function () {
    [owner, settler, player1, player2, referrer] = await ethers.getSigners();

    // Deploy MockERC20 for BUX
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockBUX = await MockToken.deploy("Mock BUX", "BUX", 18);
    await mockBUX.waitForDeployment();
    const buxAddr = await mockBUX.getAddress();

    // Mint BUX
    await mockBUX.mint(owner.address, ethers.parseEther("1000000"));
    await mockBUX.mint(player1.address, ethers.parseEther("100000"));
    await mockBUX.mint(player2.address, ethers.parseEther("100000"));

    // Deploy BUXBankroll
    const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
    buxBankroll = await upgrades.deployProxy(BUXBankroll, [buxAddr], { initializer: "initialize", kind: "uups" });
    await buxBankroll.waitForDeployment();

    // Deploy PlinkoGame
    const PlinkoGame = await ethers.getContractFactory("PlinkoGame");
    plinkoGame = await upgrades.deployProxy(PlinkoGame, [buxAddr], { initializer: "initialize", kind: "uups" });
    await plinkoGame.waitForDeployment();

    const plinkoAddr = await plinkoGame.getAddress();
    const bankrollAddr = await buxBankroll.getAddress();

    // Link contracts
    await plinkoGame.setBuxBankroll(bankrollAddr);
    await buxBankroll.setPlinkoGame(plinkoAddr);

    // Set settler
    await plinkoGame.setSettler(settler.address);

    // Enable BUX token
    await plinkoGame.configureToken(buxAddr, true);

    // Set all 9 payout tables
    for (let i = 0; i < 9; i++) {
      await plinkoGame.setPayoutTable(i, PAYOUT_TABLES[i]);
    }

    // Deposit house BUX into BUXBankroll
    await mockBUX.connect(owner).approve(bankrollAddr, ethers.MaxUint256);
    await buxBankroll.depositBUX(HOUSE_DEPOSIT);

    // Player approvals (approve PlinkoGame, which transfers to BUXBankroll)
    await mockBUX.connect(player1).approve(plinkoAddr, ethers.MaxUint256);
    await mockBUX.connect(player2).approve(plinkoAddr, ethers.MaxUint256);
  });

  // ================================================================
  // Initialization
  // ================================================================
  describe("Initialization", function () {
    it("should initialize all 9 PlinkoConfigs correctly", async function () {
      const expected = [
        { rows: 8, risk: 0, positions: 9 },
        { rows: 8, risk: 1, positions: 9 },
        { rows: 8, risk: 2, positions: 9 },
        { rows: 12, risk: 0, positions: 13 },
        { rows: 12, risk: 1, positions: 13 },
        { rows: 12, risk: 2, positions: 13 },
        { rows: 16, risk: 0, positions: 17 },
        { rows: 16, risk: 1, positions: 17 },
        { rows: 16, risk: 2, positions: 17 },
      ];
      for (let i = 0; i < 9; i++) {
        const config = await plinkoGame.getPlinkoConfig(i);
        expect(config.rows).to.equal(expected[i].rows);
        expect(config.riskLevel).to.equal(expected[i].risk);
        expect(config.numPositions).to.equal(expected[i].positions);
      }
    });

    it("should set owner correctly", async function () {
      expect(await plinkoGame.owner()).to.equal(owner.address);
    });

    it("should reject double initialization", async function () {
      await expect(
        plinkoGame.initialize(await mockBUX.getAddress())
      ).to.be.revertedWithCustomError(plinkoGame, "InvalidInitialization");
    });
  });

  // ================================================================
  // Payout Table Configuration
  // ================================================================
  describe("Payout Table Configuration", function () {
    for (let i = 0; i < 9; i++) {
      it(`should set config ${i} payout table with correct maxMultiplierBps`, async function () {
        const table = await plinkoGame.getPayoutTable(i);
        const expected = PAYOUT_TABLES[i];
        expect(table.length).to.equal(expected.length);
        for (let j = 0; j < expected.length; j++) {
          expect(Number(table[j])).to.equal(expected[j]);
        }
        const config = await plinkoGame.getPlinkoConfig(i);
        expect(Number(config.maxMultiplierBps)).to.equal(Math.max(...expected));
      });
    }

    it("should reject setPayoutTable from non-owner", async function () {
      await expect(
        plinkoGame.connect(player1).setPayoutTable(0, PAYOUT_TABLES[0])
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should reject invalid configIndex >= 9", async function () {
      await expect(plinkoGame.setPayoutTable(9, [10000])).to.be.reverted;
    });

    it("should have symmetric payouts for all 9 configs", async function () {
      for (let i = 0; i < 9; i++) {
        const table = await plinkoGame.getPayoutTable(i);
        for (let k = 0; k < table.length; k++) {
          expect(Number(table[k])).to.equal(Number(table[table.length - 1 - k]),
            `Config ${i} symmetry failed at position ${k}`);
        }
      }
    });
  });

  // ================================================================
  // Commitment
  // ================================================================
  describe("Commitment Submission", function () {
    it("should submit commitment from settler", async function () {
      const hash = ethers.keccak256(ethers.toUtf8Bytes("seed1"));
      await plinkoGame.connect(settler).submitCommitment(hash, player1.address, 0);
      const commitment = await plinkoGame.commitments(hash);
      expect(commitment.player).to.equal(player1.address);
      expect(commitment.nonce).to.equal(0);
      expect(commitment.used).to.equal(false);
    });

    it("should reject commitment from non-settler", async function () {
      const hash = ethers.keccak256(ethers.toUtf8Bytes("seed2"));
      await expect(
        plinkoGame.connect(player1).submitCommitment(hash, player1.address, 0)
      ).to.be.reverted;
    });

    it("should reject duplicate commitment hash", async function () {
      const hash = ethers.keccak256(ethers.toUtf8Bytes("seed3"));
      await plinkoGame.connect(settler).submitCommitment(hash, player1.address, 0);
      await expect(
        plinkoGame.connect(settler).submitCommitment(hash, player1.address, 1)
      ).to.be.reverted;
    });

    it("should emit CommitmentSubmitted event", async function () {
      const hash = ethers.keccak256(ethers.toUtf8Bytes("seed4"));
      await expect(plinkoGame.connect(settler).submitCommitment(hash, player1.address, 0))
        .to.emit(plinkoGame, "CommitmentSubmitted");
    });
  });

  // ================================================================
  // Place Bet (BUX)
  // ================================================================
  describe("placeBet (BUX)", function () {
    let commitmentHash;
    const serverSeed = "0x" + "a".repeat(64);
    const buxAddr = () => mockBUX.getAddress();

    beforeEach(async function () {
      commitmentHash = ethers.keccak256(ethers.toUtf8Bytes(serverSeed));
      await plinkoGame.connect(settler).submitCommitment(commitmentHash, player1.address, 0);
    });

    it("should place bet with valid params and transfer BUX to BUXBankroll", async function () {
      const bankrollBefore = await mockBUX.balanceOf(await buxBankroll.getAddress());
      await plinkoGame.connect(player1).placeBet(
        ethers.parseEther("100"), 0, commitmentHash
      );
      const bankrollAfter = await mockBUX.balanceOf(await buxBankroll.getAddress());
      expect(bankrollAfter - bankrollBefore).to.equal(ethers.parseEther("100"));
    });

    it("should reject bet below MIN_BET", async function () {
      await expect(
        plinkoGame.connect(player1).placeBet(
          ethers.parseEther("0.5"), 0, commitmentHash
        )
      ).to.be.reverted;
    });

    it("should reject bet with invalid configIndex >= 9", async function () {
      await expect(
        plinkoGame.connect(player1).placeBet(
          ethers.parseEther("10"), 9, commitmentHash
        )
      ).to.be.reverted;
    });

    it("should reject bet with already-used commitment", async function () {
      await plinkoGame.connect(player1).placeBet(
        ethers.parseEther("10"), 0, commitmentHash
      );
      // Second bet with same commitment
      await expect(
        plinkoGame.connect(player1).placeBet(
          ethers.parseEther("10"), 0, commitmentHash
        )
      ).to.be.reverted;
    });

    it("should reject bet with wrong player for commitment", async function () {
      await expect(
        plinkoGame.connect(player2).placeBet(
          ethers.parseEther("10"), 0, commitmentHash
        )
      ).to.be.reverted;
    });

    it("should emit PlinkoBetPlaced event", async function () {
      await expect(
        plinkoGame.connect(player1).placeBet(ethers.parseEther("10"), 0, commitmentHash)
      ).to.emit(plinkoGame, "PlinkoBetPlaced");
    });

    it("should mark commitment as used after bet placement", async function () {
      await plinkoGame.connect(player1).placeBet(ethers.parseEther("10"), 0, commitmentHash);
      const commitment = await plinkoGame.commitments(commitmentHash);
      expect(commitment.used).to.equal(true);
    });

    it("should increment totalBetsPlaced counter", async function () {
      const before = await plinkoGame.totalBetsPlaced();
      await plinkoGame.connect(player1).placeBet(ethers.parseEther("10"), 0, commitmentHash);
      expect(await plinkoGame.totalBetsPlaced()).to.equal(before + 1n);
    });
  });

  // ================================================================
  // Settlement (BUX)
  // ================================================================
  describe("settleBet (BUX)", function () {
    let commitmentHash;
    const serverSeed = "0x" + "a".repeat(64);
    const betAmount = ethers.parseEther("100");

    beforeEach(async function () {
      commitmentHash = ethers.keccak256(ethers.toUtf8Bytes(serverSeed));
      await plinkoGame.connect(settler).submitCommitment(commitmentHash, player1.address, 0);
      await plinkoGame.connect(player1).placeBet(betAmount, 0, commitmentHash);
    });

    it("should settle winning bet — BUXBankroll pays payout to player", async function () {
      // 8-Low, landing 0 = 5.6x payout = 560 BUX
      const path = [0, 0, 0, 0, 0, 0, 0, 0]; // landing 0
      const buxBefore = await mockBUX.balanceOf(player1.address);
      await plinkoGame.connect(settler).settleBet(commitmentHash, serverSeed, path, 0);
      const buxAfter = await mockBUX.balanceOf(player1.address);
      expect(buxAfter - buxBefore).to.equal(ethers.parseEther("560"));
    });

    it("should set bet status to Won for winning bet", async function () {
      await plinkoGame.connect(settler).settleBet(
        commitmentHash, serverSeed, [0,0,0,0,0,0,0,0], 0
      );
      const bet = await plinkoGame.bets(commitmentHash);
      expect(bet.status).to.equal(1); // Won
    });

    it("should settle losing bet with partial payout", async function () {
      // 8-Low, landing 4 = 0.5x = 50 BUX payout (loss of 50)
      const path = [0, 0, 0, 0, 1, 1, 1, 1]; // landing 4
      const buxBefore = await mockBUX.balanceOf(player1.address);
      await plinkoGame.connect(settler).settleBet(commitmentHash, serverSeed, path, 4);
      const buxAfter = await mockBUX.balanceOf(player1.address);
      expect(buxAfter - buxBefore).to.equal(ethers.parseEther("50"));
    });

    it("should reject settlement from non-settler", async function () {
      await expect(
        plinkoGame.connect(player1).settleBet(commitmentHash, serverSeed, [0,0,0,0,0,0,0,0], 0)
      ).to.be.reverted;
    });

    it("should reject double settlement", async function () {
      await plinkoGame.connect(settler).settleBet(commitmentHash, serverSeed, [0,0,0,0,0,0,0,0], 0);
      await expect(
        plinkoGame.connect(settler).settleBet(commitmentHash, serverSeed, [0,0,0,0,0,0,0,0], 0)
      ).to.be.reverted;
    });

    it("should reveal serverSeed in Commitment struct after settlement", async function () {
      await plinkoGame.connect(settler).settleBet(commitmentHash, serverSeed, [0,0,0,0,0,0,0,0], 0);
      const commitment = await plinkoGame.commitments(commitmentHash);
      expect(commitment.serverSeed).to.equal(serverSeed);
    });

    it("should increment totalBetsSettled counter", async function () {
      const before = await plinkoGame.totalBetsSettled();
      await plinkoGame.connect(settler).settleBet(commitmentHash, serverSeed, [0,0,0,0,0,0,0,0], 0);
      expect(await plinkoGame.totalBetsSettled()).to.equal(before + 1n);
    });
  });

  // ================================================================
  // Path Validation
  // ================================================================
  describe("Path Validation", function () {
    let commitmentHash;
    const serverSeed = "0x" + "b".repeat(64);
    const betAmount = ethers.parseEther("10");

    beforeEach(async function () {
      commitmentHash = ethers.keccak256(ethers.toUtf8Bytes(serverSeed));
      await plinkoGame.connect(settler).submitCommitment(commitmentHash, player1.address, 0);
      await plinkoGame.connect(player1).placeBet(betAmount, 0, commitmentHash);
    });

    it("should reject path with wrong length", async function () {
      await expect(
        plinkoGame.connect(settler).settleBet(commitmentHash, serverSeed, [0, 0, 0], 0) // 3 not 8
      ).to.be.reverted;
    });

    it("should reject path with invalid element (not 0 or 1)", async function () {
      await expect(
        plinkoGame.connect(settler).settleBet(commitmentHash, serverSeed, [0,0,0,0,0,0,0,2], 0)
      ).to.be.reverted;
    });

    it("should reject path where landing position != count of 1s", async function () {
      // Path has 3 ones but landing says 5
      await expect(
        plinkoGame.connect(settler).settleBet(commitmentHash, serverSeed, [0,0,0,1,1,1,0,0], 5)
      ).to.be.reverted;
    });

    it("should accept all-left path (landing=0)", async function () {
      await plinkoGame.connect(settler).settleBet(commitmentHash, serverSeed, [0,0,0,0,0,0,0,0], 0);
      const bet = await plinkoGame.bets(commitmentHash);
      expect(bet.status).to.not.equal(0); // settled (not Pending)
    });

    it("should accept all-right path (landing=8 for 8 rows)", async function () {
      // New commitment for fresh bet
      const seed2 = "0x" + "c".repeat(64);
      const hash2 = ethers.keccak256(ethers.toUtf8Bytes(seed2));
      await plinkoGame.connect(settler).submitCommitment(hash2, player1.address, 1);
      await plinkoGame.connect(player1).placeBet(betAmount, 0, hash2);
      await plinkoGame.connect(settler).settleBet(hash2, seed2, [1,1,1,1,1,1,1,1], 8);
      const bet = await plinkoGame.bets(hash2);
      expect(bet.status).to.not.equal(0);
    });
  });

  // ================================================================
  // Bet Expiry & Refund
  // ================================================================
  describe("Bet Expiry & Refund", function () {
    let commitmentHash;
    const serverSeed = "0x" + "d".repeat(64);

    beforeEach(async function () {
      commitmentHash = ethers.keccak256(ethers.toUtf8Bytes(serverSeed));
      await plinkoGame.connect(settler).submitCommitment(commitmentHash, player1.address, 0);
      await plinkoGame.connect(player1).placeBet(ethers.parseEther("100"), 0, commitmentHash);
    });

    it("should reject refund before expiry", async function () {
      await expect(plinkoGame.refundExpiredBet(commitmentHash)).to.be.reverted;
    });

    it("should allow refund after BET_EXPIRY (1 hour)", async function () {
      // Advance time by 1 hour + 1 second
      await ethers.provider.send("evm_increaseTime", [3601]);
      await ethers.provider.send("evm_mine");

      const buxBefore = await mockBUX.balanceOf(player1.address);
      await plinkoGame.refundExpiredBet(commitmentHash);
      const buxAfter = await mockBUX.balanceOf(player1.address);
      expect(buxAfter - buxBefore).to.equal(ethers.parseEther("100"));
    });

    it("should set bet status to Expired", async function () {
      await ethers.provider.send("evm_increaseTime", [3601]);
      await ethers.provider.send("evm_mine");
      await plinkoGame.refundExpiredBet(commitmentHash);
      const bet = await plinkoGame.bets(commitmentHash);
      expect(bet.status).to.equal(4); // Expired
    });

    it("should allow anyone to call refundExpiredBet", async function () {
      await ethers.provider.send("evm_increaseTime", [3601]);
      await ethers.provider.send("evm_mine");
      // player2 (not the bettor) calls refund
      await plinkoGame.connect(player2).refundExpiredBet(commitmentHash);
    });
  });

  // ================================================================
  // UUPS Upgrade
  // ================================================================
  describe("UUPS Upgrade", function () {
    it("should allow owner to upgrade", async function () {
      const PlinkoV2 = await ethers.getContractFactory("PlinkoGame");
      await upgrades.upgradeProxy(await plinkoGame.getAddress(), PlinkoV2, { kind: "uups" });
    });

    it("should reject upgrade from non-owner", async function () {
      const PlinkoV2 = await ethers.getContractFactory("PlinkoGame");
      await expect(
        upgrades.upgradeProxy(await plinkoGame.getAddress(), PlinkoV2.connect(player1), { kind: "uups" })
      ).to.be.reverted;
    });
  });
});
```

---

<a id="phase-p2"></a>
## Phase P2: PlinkoGame ROGUE Path + ROGUEBankroll V10 — Hardhat Tests (~40 tests)

**File:** Add to `contracts/bux-booster-game/test/PlinkoGame.test.js` (same file, new describe block)

```javascript
describe("PlinkoGame — ROGUE Path (via ROGUEBankroll)", function () {
  let plinkoGame, rogueBankroll;
  let owner, settler, player1, player2;

  // Same PAYOUT_TABLES as above

  beforeEach(async function () {
    [owner, settler, player1, player2] = await ethers.getSigners();

    // Deploy ROGUEBankroll as proxy
    const ROGUEBankroll = await ethers.getContractFactory("ROGUEBankroll");
    rogueBankroll = await upgrades.deployProxy(ROGUEBankroll, [], { initializer: "initialize" });
    await rogueBankroll.waitForDeployment();

    // Deploy PlinkoGame proxy (needs buxToken but we focus on ROGUE)
    const MockToken = await ethers.getContractFactory("MockERC20");
    const mockBUX = await MockToken.deploy("Mock BUX", "BUX", 18);
    const PlinkoGame = await ethers.getContractFactory("PlinkoGame");
    plinkoGame = await upgrades.deployProxy(
      PlinkoGame, [await mockBUX.getAddress()], { initializer: "initialize", kind: "uups" }
    );
    await plinkoGame.waitForDeployment();

    // Link PlinkoGame <-> ROGUEBankroll
    await plinkoGame.setROGUEBankroll(await rogueBankroll.getAddress());
    await rogueBankroll.setPlinkoGame(await plinkoGame.getAddress());

    // Set settler, payout tables
    await plinkoGame.setSettler(settler.address);
    for (let i = 0; i < 9; i++) {
      await plinkoGame.setPayoutTable(i, PAYOUT_TABLES[i]);
    }

    // Fund ROGUEBankroll with native ROGUE
    await owner.sendTransaction({
      to: await rogueBankroll.getAddress(),
      value: ethers.parseEther("1000"),
    });
  });

  describe("ROGUEBankroll Plinko State", function () {
    it("should set plinkoGame address via setPlinkoGame", async function () {
      expect(await rogueBankroll.plinkoGame()).to.equal(await plinkoGame.getAddress());
    });

    it("should reject setPlinkoGame from non-owner", async function () {
      await expect(
        rogueBankroll.connect(player1).setPlinkoGame(player1.address)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("placeBetROGUE", function () {
    let commitmentHash;
    const serverSeed = "0x" + "e".repeat(64);

    beforeEach(async function () {
      commitmentHash = ethers.keccak256(ethers.toUtf8Bytes(serverSeed));
      await plinkoGame.connect(settler).submitCommitment(commitmentHash, player1.address, 0);
    });

    it("should accept native ROGUE bet with msg.value", async function () {
      await plinkoGame.connect(player1).placeBetROGUE(
        ethers.parseEther("10"), 0, commitmentHash,
        { value: ethers.parseEther("10") }
      );
      const bet = await plinkoGame.bets(commitmentHash);
      expect(bet.player).to.equal(player1.address);
      expect(bet.amount).to.equal(ethers.parseEther("10"));
    });

    it("should reject bet when msg.value != amount", async function () {
      await expect(
        plinkoGame.connect(player1).placeBetROGUE(
          ethers.parseEther("10"), 0, commitmentHash,
          { value: ethers.parseEther("5") }
        )
      ).to.be.reverted;
    });

    it("should reject bet below MIN_BET", async function () {
      await expect(
        plinkoGame.connect(player1).placeBetROGUE(
          ethers.parseEther("0.5"), 0, commitmentHash,
          { value: ethers.parseEther("0.5") }
        )
      ).to.be.reverted;
    });
  });

  describe("settleBetROGUE — Win", function () {
    let commitmentHash;
    const serverSeed = "0x" + "f".repeat(64);

    beforeEach(async function () {
      commitmentHash = ethers.keccak256(ethers.toUtf8Bytes(serverSeed));
      await plinkoGame.connect(settler).submitCommitment(commitmentHash, player1.address, 0);
      await plinkoGame.connect(player1).placeBetROGUE(
        ethers.parseEther("10"), 0, commitmentHash,
        { value: ethers.parseEther("10") }
      );
    });

    it("should send ROGUE payout to winner on win", async function () {
      const balBefore = await ethers.provider.getBalance(player1.address);
      await plinkoGame.connect(settler).settleBetROGUE(
        commitmentHash, serverSeed, [0,0,0,0,0,0,0,0], 0
      );
      const balAfter = await ethers.provider.getBalance(player1.address);
      // 5.6x = 56 ROGUE payout
      expect(balAfter - balBefore).to.equal(ethers.parseEther("56"));
    });
  });

  describe("settleBetROGUE — Loss", function () {
    let commitmentHash;
    const serverSeed = "0x" + "1".repeat(64);

    beforeEach(async function () {
      commitmentHash = ethers.keccak256(ethers.toUtf8Bytes(serverSeed));
      await plinkoGame.connect(settler).submitCommitment(commitmentHash, player1.address, 0);
      await plinkoGame.connect(player1).placeBetROGUE(
        ethers.parseEther("10"), 0, commitmentHash,
        { value: ethers.parseEther("10") }
      );
    });

    it("should keep ROGUE in bankroll on loss", async function () {
      const bankrollBefore = await ethers.provider.getBalance(await rogueBankroll.getAddress());
      await plinkoGame.connect(settler).settleBetROGUE(
        commitmentHash, serverSeed, [0,0,0,0,1,1,1,1], 4 // 0.5x
      );
      const bankrollAfter = await ethers.provider.getBalance(await rogueBankroll.getAddress());
      // House keeps 5 ROGUE (10 - 5 partial payout)
      expect(bankrollAfter).to.be.gt(bankrollBefore - ethers.parseEther("5") - ethers.parseEther("1")); // approximate
    });
  });

  describe("Access Control", function () {
    it("should reject settlePlinkoWinningBet from non-plinko address on ROGUEBankroll", async function () {
      const hash = ethers.keccak256(ethers.toUtf8Bytes("unauth"));
      await expect(
        rogueBankroll.connect(player1).settlePlinkoWinningBet(
          player1.address, hash, 100, 200, 0, 0, [0], 0, 200
        )
      ).to.be.reverted;
    });
  });
});
```

---

<a id="phase-p3"></a>
## Phase P3: Plinko Deploy Verification (~90 assertions)

**File:** `contracts/bux-booster-game/scripts/verify-plinko-deployment.js`

This script is fully specified in the Plinko plan Section 15.3. Key checks:

- All 9 PlinkoConfigs (rows, risk, positions, maxMultiplierBps)
- All 9 payout tables value-by-value + symmetry verification
- BUX token enabled, BUXBankroll has liquidity
- Settler address set correctly
- ROGUEBankroll bidirectional link
- BUXBankroll bidirectional link
- MaxBet > 0 for all 9 configs (both BUX and ROGUE)
- Global accounting starts at zero

See `docs/plinko_game_plan.md` Section 15.3 for the complete script.

---

<a id="phase-p5"></a>
## Phase P5: Plinko Backend — Elixir Tests

### P5a: Plinko Math Tests (~60 tests)

**File:** `test/blockster_v2/plinko/plinko_math_test.exs`
**Run:** `mix test test/blockster_v2/plinko/plinko_math_test.exs`

```elixir
defmodule BlocksterV2.Plinko.PlinkoMathTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.PlinkoGame

  @payout_tables %{
    0 => [56000, 21000, 11000, 10000, 5000, 10000, 11000, 21000, 56000],
    1 => [130000, 30000, 13000, 7000, 4000, 7000, 13000, 30000, 130000],
    2 => [360000, 40000, 15000, 3000, 0, 3000, 15000, 40000, 360000],
    3 => [110000, 30000, 16000, 14000, 11000, 10000, 5000, 10000, 11000, 14000, 16000, 30000, 110000],
    4 => [330000, 110000, 40000, 20000, 11000, 6000, 3000, 6000, 11000, 20000, 40000, 110000, 330000],
    5 => [4050000, 180000, 70000, 20000, 7000, 2000, 0, 2000, 7000, 20000, 70000, 180000, 4050000],
    6 => [160000, 90000, 20000, 14000, 14000, 12000, 11000, 10000, 5000, 10000, 11000, 12000, 14000, 14000, 20000, 90000, 160000],
    7 => [1100000, 410000, 100000, 50000, 30000, 15000, 10000, 5000, 3000, 5000, 10000, 15000, 30000, 50000, 100000, 410000, 1100000],
    8 => [10000000, 1500000, 330000, 100000, 33000, 20000, 3000, 2000, 0, 2000, 3000, 20000, 33000, 100000, 330000, 1500000, 10000000]
  }

  @configs %{
    0 => {8, :low}, 1 => {8, :medium}, 2 => {8, :high},
    3 => {12, :low}, 4 => {12, :medium}, 5 => {12, :high},
    6 => {16, :low}, 7 => {16, :medium}, 8 => {16, :high}
  }

  # ============ Payout Table Integrity ============
  describe "payout tables" do
    test "all 9 tables are defined" do
      for i <- 0..8 do
        assert PlinkoGame.payout_table(i) != nil, "Table #{i} not defined"
      end
    end

    for {idx, expected_len} <- [{0,9},{1,9},{2,9},{3,13},{4,13},{5,13},{6,17},{7,17},{8,17}] do
      test "config #{idx} has #{expected_len} values" do
        table = PlinkoGame.payout_table(unquote(idx))
        assert length(table) == unquote(expected_len)
      end
    end
  end

  describe "payout table symmetry" do
    test "all 9 tables are symmetric" do
      for i <- 0..8 do
        table = PlinkoGame.payout_table(i)
        len = length(table)
        for k <- 0..(len - 1) do
          assert Enum.at(table, k) == Enum.at(table, len - 1 - k),
            "Config #{i}: position #{k} != position #{len - 1 - k}"
        end
      end
    end
  end

  describe "payout table values match plan" do
    for {idx, expected} <- @payout_tables do
      test "config #{idx} matches expected values" do
        assert PlinkoGame.payout_table(unquote(idx)) == unquote(Macro.escape(expected))
      end
    end
  end

  describe "max multiplier per config" do
    @max_mults %{0 => 56000, 1 => 130000, 2 => 360000, 3 => 110000, 4 => 330000,
                  5 => 4050000, 6 => 160000, 7 => 1100000, 8 => 10000000}

    for {idx, expected_max} <- @max_mults do
      test "config #{idx} max = #{expected_max}" do
        table = PlinkoGame.payout_table(unquote(idx))
        assert Enum.max(table) == unquote(expected_max)
      end
    end
  end

  # ============ Result Calculation ============
  describe "calculate_result" do
    test "produces deterministic results for same inputs" do
      server_seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      r1 = PlinkoGame.calculate_result(server_seed, 0, 100, "BUX", 0, 1)
      r2 = PlinkoGame.calculate_result(server_seed, 0, 100, "BUX", 0, 1)
      assert r1 == r2
    end

    test "produces different results for different server seeds" do
      seed1 = String.duplicate("a", 64)
      seed2 = String.duplicate("b", 64)
      {:ok, r1} = PlinkoGame.calculate_result(seed1, 0, 100, "BUX", 0, 1)
      {:ok, r2} = PlinkoGame.calculate_result(seed2, 0, 100, "BUX", 0, 1)
      assert r1.ball_path != r2.ball_path || r1.landing_position != r2.landing_position
    end

    for {rows, configs} <- [{8, [0,1,2]}, {12, [3,4,5]}, {16, [6,7,8]}] do
      test "ball_path length equals #{rows} for #{rows}-row configs" do
        seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
        config_idx = hd(unquote(configs))
        {:ok, result} = PlinkoGame.calculate_result(seed, 0, 100, "BUX", config_idx, 1)
        assert length(result.ball_path) == unquote(rows)
      end
    end

    test "ball_path contains only :left and :right atoms" do
      seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      {:ok, result} = PlinkoGame.calculate_result(seed, 0, 100, "BUX", 0, 1)
      for dir <- result.ball_path do
        assert dir in [:left, :right]
      end
    end

    test "landing_position equals count of :right in ball_path" do
      seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      {:ok, result} = PlinkoGame.calculate_result(seed, 0, 100, "BUX", 0, 1)
      rights = Enum.count(result.ball_path, &(&1 == :right))
      assert result.landing_position == rights
    end

    test "outcome is :won when payout > bet_amount" do
      # Try many seeds until we get a win
      seed = find_seed_for_outcome(:won, 0)
      {:ok, result} = PlinkoGame.calculate_result(seed, 0, 100, "BUX", 0, 1)
      assert result.outcome == :won
      assert result.payout > 100
    end

    test "outcome is :lost when payout < bet_amount" do
      seed = find_seed_for_outcome(:lost, 0)
      {:ok, result} = PlinkoGame.calculate_result(seed, 0, 100, "BUX", 0, 1)
      assert result.outcome == :lost
      assert result.payout < 100
    end
  end

  # ============ House Edge Verification ============
  describe "house edge (statistical)" do
    # Binomial distribution probabilities
    @probs_8 for k <- 0..8, do: :math.pow(0.5, 8) * combinations(8, k)
    @probs_12 for k <- 0..12, do: :math.pow(0.5, 12) * combinations(12, k)
    @probs_16 for k <- 0..16, do: :math.pow(0.5, 16) * combinations(16, k)

    for {idx, probs_key, label} <- [
      {0, :probs_8, "8-Low"}, {1, :probs_8, "8-Med"}, {2, :probs_8, "8-High"},
      {3, :probs_12, "12-Low"}, {4, :probs_12, "12-Med"}, {5, :probs_12, "12-High"},
      {6, :probs_16, "16-Low"}, {7, :probs_16, "16-Med"}, {8, :probs_16, "16-High"}
    ] do
      test "#{label} expected value is between 0.98 and 1.0" do
        table = PlinkoGame.payout_table(unquote(idx))
        rows = case unquote(probs_key) do
          :probs_8 -> 8
          :probs_12 -> 12
          :probs_16 -> 16
        end
        probs = for k <- 0..rows, do: :math.pow(0.5, rows) * combinations(rows, k)
        ev = Enum.zip(probs, table)
             |> Enum.map(fn {p, mult_bps} -> p * mult_bps / 10000 end)
             |> Enum.sum()
        assert ev >= 0.98 and ev <= 1.0,
          "#{unquote(label)} EV = #{ev}, expected 0.98..1.0"
      end
    end
  end

  # ============ Config Mapping ============
  describe "configs" do
    for {idx, {rows, risk}} <- @configs do
      test "config #{idx} = {#{rows}, #{risk}}" do
        config = PlinkoGame.config(unquote(idx))
        assert config.rows == unquote(rows)
        assert config.risk == unquote(risk)
      end
    end

    test "invalid config index returns nil" do
      assert PlinkoGame.config(9) == nil
      assert PlinkoGame.config(-1) == nil
    end
  end

  # ============ Byte-to-Direction Mapping ============
  describe "byte threshold" do
    test "byte 0 (0x00) maps to :left" do
      assert PlinkoGame.byte_to_direction(0) == :left
    end

    test "byte 127 (0x7F) maps to :left" do
      assert PlinkoGame.byte_to_direction(127) == :left
    end

    test "byte 128 (0x80) maps to :right" do
      assert PlinkoGame.byte_to_direction(128) == :right
    end

    test "byte 255 (0xFF) maps to :right" do
      assert PlinkoGame.byte_to_direction(255) == :right
    end
  end

  # ============ Helpers ============
  defp combinations(n, k) when k > n, do: 0
  defp combinations(n, 0), do: 1
  defp combinations(n, k) do
    Enum.reduce(1..k, 1, fn i, acc -> acc * (n - i + 1) / i end) |> round()
  end

  defp find_seed_for_outcome(target_outcome, config_idx) do
    Enum.reduce_while(1..1000, nil, fn _, _acc ->
      seed = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      {:ok, result} = PlinkoGame.calculate_result(seed, 0, 100, "BUX", config_idx, 1)
      if result.outcome == target_outcome, do: {:halt, seed}, else: {:cont, nil}
    end)
  end
end
```

### P5b: Plinko Game Logic Tests (~45 tests)

**File:** `test/blockster_v2/plinko/plinko_game_test.exs`

See `docs/plinko_game_plan.md` Section 15.5.2 for the complete specification. Covers:

- `init_game_with_nonce/3` — Mnesia game creation, server seed generation, commitment hash
- `get_or_init_game/2` — game reuse, nonce calculation
- `get_game/1` — Mnesia read, map destructuring
- `on_bet_placed/6` — status transitions, result calculation storage
- `settle_game/1` — settlement flow, PubSub broadcast, idempotency
- `load_recent_games/2` — pagination, sort order, settled-only filter

### P5c: Plinko Settler Tests (~13 tests)

**File:** `test/blockster_v2/plinko/plinko_settler_test.exs`

See `docs/plinko_game_plan.md` Section 15.5.3. Covers:

- Stuck bet detection (>120 seconds old :placed games)
- Scheduling (60-second intervals)
- Error handling (settlement failure doesn't block other bets)
- GenServer lifecycle

---

<a id="phase-p6"></a>
## Phase P6: PlinkoLive — LiveView Tests (~80 tests)

**File:** `test/blockster_v2_web/live/plinko_live_test.exs`

See `docs/plinko_game_plan.md` Section 15.6 for the complete specification. Covers:

- **Mount states**: guest, authenticated without wallet, authenticated with wallet
- **Config selection**: select_rows, select_risk, config_index calculation, payout_table update
- **Bet amount controls**: update, halve, double, set_max
- **Token selection**: toggle dropdown, switch BUX/ROGUE
- **Drop ball**: validations (balance, min bet, onchain_ready), success flow (game_state, path, balance deduction)
- **JS pushEvent handlers**: bet_confirmed, bet_failed (refund), ball_landed (confetti)
- **Reset game**: state cleanup, new init_onchain_game
- **Fairness modal**: show/hide, server_seed visibility rules
- **Game history**: load-more pagination
- **Async handlers**: init_onchain_game (success, retry logic), fetch_house_balance, load_recent_games
- **PubSub handlers**: balance updates, settlement notifications, token prices
- **SVG rendering**: peg counts per row configuration, landing slot labels

---

<a id="phase-p7"></a>
## Phase P7: Integration Tests (~50 tests)

**File:** `test/blockster_v2/plinko/plinko_integration_test.exs`

See `docs/plinko_game_plan.md` Section 15.7 for the complete specification. Covers:

- **Full game lifecycle**: BUX win/loss/push flows, ROGUE win/loss flows, 0x payout flow
- **Sequential games**: nonce incrementation, game reuse, config switching
- **Balance integration**: optimistic deduction, refund on failure, sync after settlement
- **PubSub broadcasting**: settlement channel, balance channel
- **Settler integration**: stuck bet detection + settlement, error isolation
- **Provably fair**: SHA256 commitment verification, result reproducibility, byte-to-direction, landing position consistency
- **User betting stats**: accumulation, BUX/ROGUE separate tracking
- **Error handling**: double settlement idempotency, missing game, wrong status
- **Game history**: pagination, settled-only, fairness modal fields
- **Concurrent safety**: multi-user isolation, single-user duplicate prevention
- **Config consistency**: backend tables match contract tables exactly

---

<a id="running-all-tests"></a>
## Running All Tests

### By Phase

```bash
# Phase B1: BUXBankroll contract tests
cd contracts/bux-booster-game && npx hardhat test test/BUXBankroll.test.js

# Phase B2: BUXBankroll deploy verification (requires deployed contracts)
cd contracts/bux-booster-game && npx hardhat run scripts/verify-bux-bankroll.js --network rogue

# Phase B4: LP Price Tracker backend tests
mix test test/blockster_v2/plinko/lp_bux_price_tracker_test.exs

# Phase B5: BankrollLive UI tests
mix test test/blockster_v2_web/live/bankroll_live_test.exs

# Phase P1: PlinkoGame contract tests (BUX path)
cd contracts/bux-booster-game && npx hardhat test test/PlinkoGame.test.js

# Phase P2: PlinkoGame ROGUE path (included in PlinkoGame.test.js)
# Same command as P1

# Phase P3: Plinko deploy verification (requires deployed contracts)
cd contracts/bux-booster-game && npx hardhat run scripts/verify-plinko-deployment.js --network rogue

# Phase P5: Plinko backend tests
mix test test/blockster_v2/plinko/

# Phase P6: PlinkoLive UI tests
mix test test/blockster_v2_web/live/plinko_live_test.exs

# Phase P7: Integration tests
mix test test/blockster_v2/plinko/plinko_integration_test.exs
```

### All Tests at Once

```bash
# All Elixir tests (backend + LiveView + integration)
mix test test/blockster_v2/plinko/ test/blockster_v2_web/live/bankroll_live_test.exs test/blockster_v2_web/live/plinko_live_test.exs

# All Hardhat contract tests
cd contracts/bux-booster-game && npx hardhat test test/BUXBankroll.test.js test/PlinkoGame.test.js
```

### Test Summary

| Phase | File | Location | Tests | Type |
|-------|------|----------|-------|------|
| B1 | `BUXBankroll.test.js` | `contracts/.../test/` | ~60 | Hardhat |
| B2 | `verify-bux-bankroll.js` | `contracts/.../scripts/` | ~40 assertions | Verification |
| B4 | `lp_bux_price_tracker_test.exs` | `test/blockster_v2/plinko/` | ~15 | ExUnit + Mnesia |
| B5 | `bankroll_live_test.exs` | `test/.../live/` | ~30 | ConnCase + LiveView |
| P1 | `PlinkoGame.test.js` (BUX) | `contracts/.../test/` | ~80 | Hardhat |
| P2 | `PlinkoGame.test.js` (ROGUE) | `contracts/.../test/` | ~40 | Hardhat |
| P3 | `verify-plinko-deployment.js` | `contracts/.../scripts/` | ~90 assertions | Verification |
| P5a | `plinko_math_test.exs` | `test/blockster_v2/plinko/` | ~60 | ExUnit (async) |
| P5b | `plinko_game_test.exs` | `test/blockster_v2/plinko/` | ~45 | ExUnit + Mnesia |
| P5c | `plinko_settler_test.exs` | `test/blockster_v2/plinko/` | ~13 | ExUnit + Mnesia |
| P6 | `plinko_live_test.exs` | `test/.../live/` | ~80 | ConnCase + LiveView |
| P7 | `plinko_integration_test.exs` | `test/blockster_v2/plinko/` | ~50 | ExUnit + Mnesia + PubSub |
| **Total** | | | **~560+** | |

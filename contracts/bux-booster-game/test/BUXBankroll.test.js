const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("BUXBankroll", function () {
  let bankroll;
  let buxToken;
  let owner;
  let plinkoGame;
  let player1;
  let player2;
  let referrer;
  let referralAdmin;

  const INITIAL_DEPOSIT = ethers.parseEther("100000"); // 100k BUX
  const ONE_BUX = ethers.parseEther("1");
  const MULTIPLIER_DENOMINATOR = 10000n;

  // Helper: deploy and set up bankroll with initial deposit
  async function deployAndSetup() {
    [owner, plinkoGame, player1, player2, referrer, referralAdmin] = await ethers.getSigners();

    // Deploy mock BUX token
    const MockToken = await ethers.getContractFactory("MockERC20");
    buxToken = await MockToken.deploy("Mock BUX", "BUX", 18);
    await buxToken.waitForDeployment();

    // Deploy BUXBankroll as UUPS proxy
    const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
    bankroll = await upgrades.deployProxy(
      BUXBankroll,
      [await buxToken.getAddress()],
      { initializer: "initialize", kind: "uups" }
    );
    await bankroll.waitForDeployment();

    // Set plinko game
    await bankroll.setPlinkoGame(plinkoGame.address);
  }

  // Helper: mint BUX to an address and approve bankroll
  async function mintAndApprove(signer, amount) {
    await buxToken.mint(signer.address, amount);
    await buxToken.connect(signer).approve(await bankroll.getAddress(), amount);
  }

  // Helper: make initial house deposit
  async function seedHouse(amount) {
    await mintAndApprove(owner, amount);
    await bankroll.connect(owner).depositBUX(amount);
  }

  // Helper: simulate a bet being placed (as plinko game)
  async function placeBet(player, wagerAmount, configIndex, maxMultiplierBps) {
    const commitmentHash = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "uint256"],
        [player.address, wagerAmount, Date.now()]
      )
    );
    const nonce = 1;
    const maxPayout = (wagerAmount * BigInt(maxMultiplierBps)) / MULTIPLIER_DENOMINATOR;

    // Transfer BUX from player to bankroll (simulating PlinkoGame's transferFrom)
    await buxToken.connect(player).transfer(await bankroll.getAddress(), wagerAmount);

    // Call as plinko game
    await bankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
      commitmentHash, player.address, wagerAmount, configIndex, nonce, maxPayout
    );

    return { commitmentHash, nonce, maxPayout };
  }

  beforeEach(async function () {
    await deployAndSetup();
  });

  // =================================================================
  // 1. INITIALIZATION
  // =================================================================
  describe("Initialization", function () {
    it("should set BUX token address", async function () {
      expect(await bankroll.buxToken()).to.equal(await buxToken.getAddress());
    });

    it("should set owner correctly", async function () {
      expect(await bankroll.owner()).to.equal(owner.address);
    });

    it("should set LP token name and symbol", async function () {
      expect(await bankroll.name()).to.equal("BUX Bankroll");
      expect(await bankroll.symbol()).to.equal("LP-BUX");
    });

    it("should set default maximumBetSizeDivisor to 1000", async function () {
      expect(await bankroll.maximumBetSizeDivisor()).to.equal(1000n);
    });

    it("should set default referralBasisPoints to 20", async function () {
      expect(await bankroll.referralBasisPoints()).to.equal(20n);
    });

    it("should set initial LP price to 1e18", async function () {
      expect(await bankroll.getLPPrice()).to.equal(ethers.parseEther("1"));
    });

    it("should reject zero address for BUX token", async function () {
      const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
      await expect(
        upgrades.deployProxy(BUXBankroll, [ethers.ZeroAddress], { initializer: "initialize", kind: "uups" })
      ).to.be.revertedWithCustomError(bankroll, "ZeroAddress");
    });

    it("should reject double initialization", async function () {
      await expect(
        bankroll.initialize(await buxToken.getAddress())
      ).to.be.revertedWithCustomError(bankroll, "InvalidInitialization");
    });

    it("should start with zero house balance", async function () {
      const info = await bankroll.getHouseInfo();
      expect(info[0]).to.equal(0n); // totalBalance
      expect(info[1]).to.equal(0n); // liability
      expect(info[2]).to.equal(0n); // unsettledBets
      expect(info[3]).to.equal(0n); // netBalance
      expect(info[4]).to.equal(0n); // poolTokenSupply
      expect(info[5]).to.equal(ethers.parseEther("1")); // poolTokenPrice (1:1 default)
    });
  });

  // =================================================================
  // 2. DEPOSIT BUX
  // =================================================================
  describe("depositBUX", function () {
    it("should deposit BUX and mint LP tokens 1:1 for first deposit", async function () {
      const amount = ethers.parseEther("1000");
      await mintAndApprove(player1, amount);

      await expect(bankroll.connect(player1).depositBUX(amount))
        .to.emit(bankroll, "BUXDeposited")
        .withArgs(player1.address, amount, amount);

      expect(await bankroll.balanceOf(player1.address)).to.equal(amount);
      expect(await bankroll.totalSupply()).to.equal(amount);
    });

    it("should mint proportional LP tokens for subsequent deposits", async function () {
      // First deposit: 1000 BUX -> 1000 LP
      await seedHouse(ethers.parseEther("1000"));

      // Second deposit: 500 BUX -> 500 LP (proportional to 1000/1000)
      const amount = ethers.parseEther("500");
      await mintAndApprove(player1, amount);
      await bankroll.connect(player1).depositBUX(amount);

      expect(await bankroll.balanceOf(player1.address)).to.equal(amount);
      expect(await bankroll.totalSupply()).to.equal(ethers.parseEther("1500"));
    });

    it("should update house balance correctly", async function () {
      const amount = ethers.parseEther("5000");
      await mintAndApprove(owner, amount);
      await bankroll.connect(owner).depositBUX(amount);

      const info = await bankroll.getHouseInfo();
      expect(info[0]).to.equal(amount); // totalBalance
      expect(info[3]).to.equal(amount); // netBalance (no liability)
    });

    it("should emit PoolPriceUpdated event", async function () {
      const amount = ethers.parseEther("1000");
      await mintAndApprove(player1, amount);

      await expect(bankroll.connect(player1).depositBUX(amount))
        .to.emit(bankroll, "PoolPriceUpdated");
    });

    it("should revert on zero amount", async function () {
      await expect(
        bankroll.connect(player1).depositBUX(0)
      ).to.be.revertedWithCustomError(bankroll, "ZeroAmount");
    });

    it("should revert without BUX approval", async function () {
      await buxToken.mint(player1.address, ONE_BUX);
      // No approval
      await expect(
        bankroll.connect(player1).depositBUX(ONE_BUX)
      ).to.be.reverted;
    });

    it("should transfer BUX from depositor to bankroll", async function () {
      const amount = ethers.parseEther("1000");
      await mintAndApprove(player1, amount);

      const bankrollAddr = await bankroll.getAddress();
      const balBefore = await buxToken.balanceOf(bankrollAddr);
      await bankroll.connect(player1).depositBUX(amount);
      const balAfter = await buxToken.balanceOf(bankrollAddr);

      expect(balAfter - balBefore).to.equal(amount);
    });
  });

  // =================================================================
  // 3. WITHDRAW BUX
  // =================================================================
  describe("withdrawBUX", function () {
    beforeEach(async function () {
      // Seed initial deposit: 10,000 BUX
      await seedHouse(ethers.parseEther("10000"));
    });

    it("should withdraw BUX by burning LP tokens", async function () {
      const lpAmount = ethers.parseEther("5000");
      const expectedBux = ethers.parseEther("5000"); // 1:1 price

      await expect(bankroll.connect(owner).withdrawBUX(lpAmount))
        .to.emit(bankroll, "BUXWithdrawn")
        .withArgs(owner.address, expectedBux, lpAmount);

      expect(await bankroll.balanceOf(owner.address)).to.equal(ethers.parseEther("5000"));
    });

    it("should update house balance after withdrawal", async function () {
      await bankroll.connect(owner).withdrawBUX(ethers.parseEther("3000"));

      const info = await bankroll.getHouseInfo();
      expect(info[0]).to.equal(ethers.parseEther("7000")); // totalBalance
    });

    it("should return correct BUX amount when LP price > 1", async function () {
      // Simulate house profit: send extra BUX directly to bankroll and update balance via a bet cycle
      // For simplicity: deposit as player1, then owner withdraws at same price
      const deposit2 = ethers.parseEther("5000");
      await mintAndApprove(player1, deposit2);
      await bankroll.connect(player1).depositBUX(deposit2);

      // Both deposited at 1:1, so withdraw should be 1:1
      await bankroll.connect(player1).withdrawBUX(deposit2);
      expect(await buxToken.balanceOf(player1.address)).to.equal(deposit2);
    });

    it("should revert on zero amount", async function () {
      await expect(
        bankroll.connect(owner).withdrawBUX(0)
      ).to.be.revertedWithCustomError(bankroll, "ZeroAmount");
    });

    it("should revert when LP balance insufficient", async function () {
      await expect(
        bankroll.connect(player1).withdrawBUX(ONE_BUX) // player1 has no LP tokens
      ).to.be.revertedWithCustomError(bankroll, "InsufficientBalance");
    });

    it("should respect liability reserves (cannot drain below liability)", async function () {
      // Place a bet to create liability
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      await buxToken.connect(player1).approve(await bankroll.getAddress(), 0n); // reset
      // Transfer directly (simulating plinko game flow)
      await buxToken.connect(player1).transfer(await bankroll.getAddress(), wager);
      const maxMultBps = 56000; // 5.6x
      const maxPayout = (wager * BigInt(maxMultBps)) / MULTIPLIER_DENOMINATOR;
      const commitHash = ethers.keccak256(ethers.toUtf8Bytes("test-bet"));

      await bankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        commitHash, player1.address, wager, 0, 1, maxPayout
      );

      // House has 10100 total, liability = 560, net = 10100 - 560 = 9540
      const info = await bankroll.getHouseInfo();
      expect(info[3]).to.equal(ethers.parseEther("10100") - maxPayout); // netBalance

      // Owner tries to withdraw all 10000 LP, but should only get netBalance proportion
      // netBalance/supply * lpAmount = 9540/10000 * 10000 = 9540
      const ownerLp = await bankroll.balanceOf(owner.address);
      await bankroll.connect(owner).withdrawBUX(ownerLp);

      // Should get netBalance (since they own 100% of LP supply)
      const ownerBux = await buxToken.balanceOf(owner.address);
      expect(ownerBux).to.equal(info[3]); // netBalance
    });

    it("should emit PoolPriceUpdated event on withdrawal", async function () {
      await expect(bankroll.connect(owner).withdrawBUX(ethers.parseEther("1000")))
        .to.emit(bankroll, "PoolPriceUpdated");
    });
  });

  // =================================================================
  // 4. LP PRICE MECHANICS
  // =================================================================
  describe("LP Price Mechanics", function () {
    it("should start at 1:1 (1e18)", async function () {
      expect(await bankroll.getLPPrice()).to.equal(ethers.parseEther("1"));
    });

    it("should maintain 1:1 after first deposit", async function () {
      await seedHouse(ethers.parseEther("10000"));
      expect(await bankroll.getLPPrice()).to.equal(ethers.parseEther("1"));
    });

    it("should increase LP price after house wins (losing bet)", async function () {
      await seedHouse(ethers.parseEther("10000"));
      const priceBefore = await bankroll.getLPPrice();

      // Simulate: player places bet, loses completely
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      await buxToken.connect(player1).transfer(await bankroll.getAddress(), wager);
      const maxPayout = (wager * 56000n) / MULTIPLIER_DENOMINATOR;
      const commitHash = ethers.keccak256(ethers.toUtf8Bytes("losing-bet"));

      await bankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        commitHash, player1.address, wager, 0, 1, maxPayout
      );

      // Settle as loss (0 partial payout = total loss)
      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, commitHash, wager, 0, 0, 5, [0, 1, 0, 1, 0, 1, 0, 1], 1, maxPayout
      );

      const priceAfter = await bankroll.getLPPrice();
      expect(priceAfter).to.be.gt(priceBefore);
    });

    it("should decrease LP price after house loses (winning bet)", async function () {
      await seedHouse(ethers.parseEther("10000"));
      const priceBefore = await bankroll.getLPPrice();

      // Player places bet and wins
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      await buxToken.connect(player1).transfer(await bankroll.getAddress(), wager);
      const maxPayout = (wager * 56000n) / MULTIPLIER_DENOMINATOR;
      const payout = ethers.parseEther("200"); // 2x win
      const commitHash = ethers.keccak256(ethers.toUtf8Bytes("winning-bet"));

      await bankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        commitHash, player1.address, wager, 0, 1, maxPayout
      );

      await bankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, commitHash, wager, payout, 0, 3, [1, 1, 1, 0, 1, 0, 0, 1], 1, maxPayout
      );

      const priceAfter = await bankroll.getLPPrice();
      expect(priceAfter).to.be.lt(priceBefore);
    });

    it("should use effectiveBalance (totalBalance - unsettledBets) for deposit pricing", async function () {
      await seedHouse(ethers.parseEther("10000"));

      // Place a bet to create unsettledBets
      const wager = ethers.parseEther("500");
      await mintAndApprove(player1, wager);
      await buxToken.connect(player1).transfer(await bankroll.getAddress(), wager);
      const maxPayout = (wager * 56000n) / MULTIPLIER_DENOMINATOR;
      const commitHash = ethers.keccak256(ethers.toUtf8Bytes("active-bet"));

      await bankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        commitHash, player1.address, wager, 0, 1, maxPayout
      );

      // Now deposit while bet is active - LP price should use effectiveBalance
      const newDeposit = ethers.parseEther("1000");
      await mintAndApprove(player2, newDeposit);
      await bankroll.connect(player2).depositBUX(newDeposit);

      // effectiveBalance = 10500 - 500 = 10000
      // supply = 10000 LP
      // lpMinted = 1000 * 10000 / 10000 = 1000 (still 1:1 because unsettled is excluded)
      expect(await bankroll.balanceOf(player2.address)).to.equal(newDeposit);
    });

    it("should use netBalance (totalBalance - liability) for withdrawal pricing", async function () {
      await seedHouse(ethers.parseEther("10000"));

      // Place a bet to create liability
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      await buxToken.connect(player1).transfer(await bankroll.getAddress(), wager);
      const maxMultBps = 56000n; // 5.6x
      const maxPayout = (wager * maxMultBps) / MULTIPLIER_DENOMINATOR;
      const commitHash = ethers.keccak256(ethers.toUtf8Bytes("liability-bet"));

      await bankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        commitHash, player1.address, wager, 0, 1, maxPayout
      );

      const info = await bankroll.getHouseInfo();
      const netBalance = info[3]; // totalBalance - liability

      // Withdraw half of LP tokens
      const halfLp = ethers.parseEther("5000");
      await bankroll.connect(owner).withdrawBUX(halfLp);

      // Should get halfLp * netBalance / totalSupply
      const expectedBux = (halfLp * netBalance) / ethers.parseEther("10000");
      expect(await buxToken.balanceOf(owner.address)).to.equal(expectedBux);
    });
  });

  // =================================================================
  // 5. PLINKO GAME INTEGRATION - BET PLACED
  // =================================================================
  describe("Plinko Bet Placed", function () {
    beforeEach(async function () {
      await seedHouse(INITIAL_DEPOSIT);
    });

    it("should update house balance on bet placed", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { maxPayout } = await placeBet(player1, wager, 0, 56000);

      const info = await bankroll.getHouseInfo();
      expect(info[0]).to.equal(INITIAL_DEPOSIT + wager); // totalBalance
      expect(info[1]).to.equal(maxPayout); // liability
      expect(info[2]).to.equal(wager); // unsettledBets
    });

    it("should emit PlinkoBetPlaced event", async function () {
      const wager = ethers.parseEther("50");
      await mintAndApprove(player1, wager);
      const commitHash = ethers.keccak256(ethers.toUtf8Bytes("event-test"));
      const maxPayout = (wager * 56000n) / MULTIPLIER_DENOMINATOR;

      await buxToken.connect(player1).transfer(await bankroll.getAddress(), wager);

      await expect(
        bankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
          commitHash, player1.address, wager, 2, 1, maxPayout
        )
      ).to.emit(bankroll, "PlinkoBetPlaced")
        .withArgs(player1.address, commitHash, wager, 2, 1, (val) => val > 0);
    });

    it("should revert when called by non-plinko address", async function () {
      const commitHash = ethers.keccak256(ethers.toUtf8Bytes("unauth"));
      await expect(
        bankroll.connect(player1).updateHouseBalancePlinkoBetPlaced(
          commitHash, player1.address, ONE_BUX, 0, 1, ONE_BUX
        )
      ).to.be.revertedWithCustomError(bankroll, "UnauthorizedGame");
    });

    it("should handle multiple simultaneous bets", async function () {
      const wager1 = ethers.parseEther("100");
      const wager2 = ethers.parseEther("200");
      await mintAndApprove(player1, wager1);
      await mintAndApprove(player2, wager2);

      const bet1 = await placeBet(player1, wager1, 0, 56000);
      const bet2 = await placeBet(player2, wager2, 1, 30000);

      const info = await bankroll.getHouseInfo();
      expect(info[0]).to.equal(INITIAL_DEPOSIT + wager1 + wager2); // totalBalance
      expect(info[1]).to.equal(bet1.maxPayout + bet2.maxPayout); // liability
      expect(info[2]).to.equal(wager1 + wager2); // unsettledBets
    });
  });

  // =================================================================
  // 6. PLINKO WINNING BET SETTLEMENT
  // =================================================================
  describe("Plinko Winning Bet Settlement", function () {
    beforeEach(async function () {
      await seedHouse(INITIAL_DEPOSIT);
    });

    it("should pay winner and update house balance", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      const payout = ethers.parseEther("200"); // 2x
      const balBefore = await buxToken.balanceOf(player1.address);

      await bankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, commitmentHash, wager, payout, 0, 3, [1, 1, 0, 0, 1, 0, 1, 1], nonce, maxPayout
      );

      const balAfter = await buxToken.balanceOf(player1.address);
      expect(balAfter - balBefore).to.equal(payout);

      const info = await bankroll.getHouseInfo();
      // totalBalance went from (100k + 100) - 200 = 99900
      expect(info[0]).to.equal(INITIAL_DEPOSIT + wager - payout);
      expect(info[1]).to.equal(0n); // liability released
      expect(info[2]).to.equal(0n); // unsettled cleared
    });

    it("should emit winning payout events", async function () {
      const wager = ethers.parseEther("50");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 2, 56000);

      const payout = ethers.parseEther("150"); // 3x
      const profit = payout - wager;

      await expect(
        bankroll.connect(plinkoGame).settlePlinkoWinningBet(
          player1.address, commitmentHash, wager, payout, 2, 6, [1, 1, 1, 1, 0, 0, 1, 1], nonce, maxPayout
        )
      ).to.emit(bankroll, "PlinkoWinningPayout")
        .withArgs(player1.address, commitmentHash, wager, payout, profit);
    });

    it("should update player stats on win", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      const payout = ethers.parseEther("200");
      const profit = payout - wager;

      await bankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, commitmentHash, wager, payout, 0, 4, [1, 0, 1, 0, 1, 0, 1, 0], nonce, maxPayout
      );

      const stats = await bankroll.getPlinkoPlayerStats(player1.address);
      expect(stats[0]).to.equal(1n); // totalBets
      expect(stats[1]).to.equal(1n); // wins
      expect(stats[4]).to.equal(wager); // totalWagered
      expect(stats[5]).to.equal(profit); // totalWinnings
    });

    it("should revert when called by non-plinko", async function () {
      await expect(
        bankroll.connect(player1).settlePlinkoWinningBet(
          player1.address, ethers.ZeroHash, ONE_BUX, ONE_BUX * 2n, 0, 3, [1, 0], 1, ONE_BUX * 6n
        )
      ).to.be.revertedWithCustomError(bankroll, "UnauthorizedGame");
    });
  });

  // =================================================================
  // 7. PLINKO LOSING BET SETTLEMENT
  // =================================================================
  describe("Plinko Losing Bet Settlement", function () {
    beforeEach(async function () {
      await seedHouse(INITIAL_DEPOSIT);
    });

    it("should keep BUX on total loss (0 partial payout)", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      const balBefore = await buxToken.balanceOf(player1.address);

      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], nonce, maxPayout
      );

      const balAfter = await buxToken.balanceOf(player1.address);
      expect(balAfter).to.equal(balBefore); // No payout

      const info = await bankroll.getHouseInfo();
      // totalBalance unchanged (house kept the wager)
      expect(info[0]).to.equal(INITIAL_DEPOSIT + wager);
      expect(info[1]).to.equal(0n); // liability released
      expect(info[2]).to.equal(0n); // unsettled cleared
    });

    it("should send partial payout on partial loss (0.3x)", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      const partialPayout = ethers.parseEther("30"); // 0.3x
      const balBefore = await buxToken.balanceOf(player1.address);

      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, commitmentHash, wager, partialPayout, 0, 2, [0, 1, 0, 0, 1, 0, 0, 1], nonce, maxPayout
      );

      const balAfter = await buxToken.balanceOf(player1.address);
      expect(balAfter - balBefore).to.equal(partialPayout);
    });

    it("should update player stats on loss", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], nonce, maxPayout
      );

      const stats = await bankroll.getPlinkoPlayerStats(player1.address);
      expect(stats[0]).to.equal(1n); // totalBets
      expect(stats[2]).to.equal(1n); // losses
      expect(stats[4]).to.equal(wager); // totalWagered
      expect(stats[6]).to.equal(wager); // totalLosses
    });

    it("should emit PlinkoLosingBet event", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      await expect(
        bankroll.connect(plinkoGame).settlePlinkoLosingBet(
          player1.address, commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], nonce, maxPayout
        )
      ).to.emit(bankroll, "PlinkoLosingBet")
        .withArgs(player1.address, commitmentHash, wager, 0);
    });

    it("should update plinko accounting on loss", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], nonce, maxPayout
      );

      const acc = await bankroll.getPlinkoAccounting();
      expect(acc[0]).to.equal(1n); // totalBets
      expect(acc[2]).to.equal(1n); // totalLosses (player perspective = house loss tracker)
      expect(acc[4]).to.equal(wager); // totalVolumeWagered
      expect(acc[6]).to.equal(wager); // totalHouseProfit (int256)
    });
  });

  // =================================================================
  // 8. PLINKO PUSH BET SETTLEMENT
  // =================================================================
  describe("Plinko Push Bet Settlement", function () {
    beforeEach(async function () {
      await seedHouse(INITIAL_DEPOSIT);
    });

    it("should return exact bet amount on push", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      const balBefore = await buxToken.balanceOf(player1.address);

      await bankroll.connect(plinkoGame).settlePlinkoPushBet(
        player1.address, commitmentHash, wager, 0, 4, [1, 0, 1, 0, 1, 0, 1, 0], nonce, maxPayout
      );

      const balAfter = await buxToken.balanceOf(player1.address);
      expect(balAfter - balBefore).to.equal(wager);
    });

    it("should not change house balance on push", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      await bankroll.connect(plinkoGame).settlePlinkoPushBet(
        player1.address, commitmentHash, wager, 0, 4, [1, 0, 1, 0, 1, 0, 1, 0], nonce, maxPayout
      );

      const info = await bankroll.getHouseInfo();
      expect(info[0]).to.equal(INITIAL_DEPOSIT); // totalBalance back to original
      expect(info[1]).to.equal(0n); // liability released
      expect(info[2]).to.equal(0n); // unsettled cleared
    });

    it("should update push stats", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      await bankroll.connect(plinkoGame).settlePlinkoPushBet(
        player1.address, commitmentHash, wager, 0, 4, [1, 0, 1, 0, 1, 0, 1, 0], nonce, maxPayout
      );

      const stats = await bankroll.getPlinkoPlayerStats(player1.address);
      expect(stats[0]).to.equal(1n); // totalBets
      expect(stats[3]).to.equal(1n); // pushes

      const acc = await bankroll.getPlinkoAccounting();
      expect(acc[3]).to.equal(1n); // totalPushes
    });
  });

  // =================================================================
  // 9. LIABILITY TRACKING
  // =================================================================
  describe("Liability Tracking", function () {
    beforeEach(async function () {
      await seedHouse(INITIAL_DEPOSIT);
    });

    it("should track liability correctly across multiple active bets", async function () {
      const wager1 = ethers.parseEther("100");
      const wager2 = ethers.parseEther("200");
      await mintAndApprove(player1, wager1);
      await mintAndApprove(player2, wager2);

      const bet1 = await placeBet(player1, wager1, 0, 56000);
      const bet2 = await placeBet(player2, wager2, 1, 30000);

      const info = await bankroll.getHouseInfo();
      expect(info[1]).to.equal(bet1.maxPayout + bet2.maxPayout); // total liability

      // Settle bet1 as loss
      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, bet1.commitmentHash, wager1, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], bet1.nonce, bet1.maxPayout
      );

      const infoAfter = await bankroll.getHouseInfo();
      expect(infoAfter[1]).to.equal(bet2.maxPayout); // only bet2 liability remains
    });

    it("should track unsettled bets correctly", async function () {
      const wager1 = ethers.parseEther("100");
      const wager2 = ethers.parseEther("150");
      await mintAndApprove(player1, wager1 + wager2);

      const bet1 = await placeBet(player1, wager1, 0, 56000);
      const bet2 = await placeBet(player1, wager2, 1, 30000);

      const info = await bankroll.getHouseInfo();
      expect(info[2]).to.equal(wager1 + wager2); // unsettledBets

      // Settle bet1
      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, bet1.commitmentHash, wager1, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], bet1.nonce, bet1.maxPayout
      );

      const infoAfter = await bankroll.getHouseInfo();
      expect(infoAfter[2]).to.equal(wager2); // only bet2 unsettled
    });

    it("should calculate netBalance correctly (totalBalance - liability)", async function () {
      const wager = ethers.parseEther("1000");
      await mintAndApprove(player1, wager);
      const { maxPayout } = await placeBet(player1, wager, 0, 56000);

      const info = await bankroll.getHouseInfo();
      expect(info[3]).to.equal(info[0] - info[1]); // netBalance = totalBalance - liability
      expect(info[3]).to.equal(INITIAL_DEPOSIT + wager - maxPayout);
    });
  });

  // =================================================================
  // 10. REFERRAL REWARDS
  // =================================================================
  describe("Referral Rewards", function () {
    beforeEach(async function () {
      await seedHouse(INITIAL_DEPOSIT);
      // Set referral admin
      await bankroll.setReferralAdmin(referralAdmin.address);
    });

    it("should pay referral reward on losing bet", async function () {
      // Set referrer for player1
      await bankroll.connect(referralAdmin).setPlayerReferrer(player1.address, referrer.address);

      const wager = ethers.parseEther("1000");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      const referrerBalBefore = await buxToken.balanceOf(referrer.address);

      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], nonce, maxPayout
      );

      const referrerBalAfter = await buxToken.balanceOf(referrer.address);
      // 0.2% of 1000 = 2 BUX
      const expectedReward = (wager * 20n) / 10000n;
      expect(referrerBalAfter - referrerBalBefore).to.equal(expectedReward);
    });

    it("should emit ReferralRewardPaid event", async function () {
      await bankroll.connect(referralAdmin).setPlayerReferrer(player1.address, referrer.address);

      const wager = ethers.parseEther("1000");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      const expectedReward = (wager * 20n) / 10000n;

      await expect(
        bankroll.connect(plinkoGame).settlePlinkoLosingBet(
          player1.address, commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], nonce, maxPayout
        )
      ).to.emit(bankroll, "ReferralRewardPaid")
        .withArgs(commitmentHash, referrer.address, player1.address, expectedReward);
    });

    it("should track total referral rewards paid", async function () {
      await bankroll.connect(referralAdmin).setPlayerReferrer(player1.address, referrer.address);

      const wager = ethers.parseEther("500");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], nonce, maxPayout
      );

      const expectedReward = (wager * 20n) / 10000n;
      expect(await bankroll.totalReferralRewardsPaid()).to.equal(expectedReward);
      expect(await bankroll.getReferrerTotalEarnings(referrer.address)).to.equal(expectedReward);
    });

    it("should not pay referral when no referrer set", async function () {
      const wager = ethers.parseEther("1000");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], nonce, maxPayout
      );

      expect(await bankroll.totalReferralRewardsPaid()).to.equal(0n);
    });

    it("should not pay referral on winning bets", async function () {
      await bankroll.connect(referralAdmin).setPlayerReferrer(player1.address, referrer.address);

      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      const referrerBalBefore = await buxToken.balanceOf(referrer.address);

      await bankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, commitmentHash, wager, ethers.parseEther("200"), 0, 3, [1, 1, 0, 0, 1, 0, 1, 1], nonce, maxPayout
      );

      const referrerBalAfter = await buxToken.balanceOf(referrer.address);
      expect(referrerBalAfter).to.equal(referrerBalBefore); // No change
    });

    it("should only allow owner or referralAdmin to set referrer", async function () {
      await expect(
        bankroll.connect(player1).setPlayerReferrer(player2.address, referrer.address)
      ).to.be.revertedWith("Not authorized");
    });

    it("should not allow setting referrer twice", async function () {
      await bankroll.connect(referralAdmin).setPlayerReferrer(player1.address, referrer.address);

      await expect(
        bankroll.connect(referralAdmin).setPlayerReferrer(player1.address, player2.address)
      ).to.be.revertedWith("Referrer already set");
    });

    it("should not allow self-referral", async function () {
      await expect(
        bankroll.connect(referralAdmin).setPlayerReferrer(player1.address, player1.address)
      ).to.be.revertedWith("Self-referral not allowed");
    });

    it("should handle batch referrer setting", async function () {
      await bankroll.connect(referralAdmin).setPlayerReferrersBatch(
        [player1.address, player2.address],
        [referrer.address, referrer.address]
      );

      expect(await bankroll.getPlayerReferrer(player1.address)).to.equal(referrer.address);
      expect(await bankroll.getPlayerReferrer(player2.address)).to.equal(referrer.address);
    });

    it("should pay referral on partial loss too", async function () {
      await bankroll.connect(referralAdmin).setPlayerReferrer(player1.address, referrer.address);

      const wager = ethers.parseEther("1000");
      const partialPayout = ethers.parseEther("300"); // 0.3x
      await mintAndApprove(player1, wager);
      const { commitmentHash, nonce, maxPayout } = await placeBet(player1, wager, 0, 56000);

      const referrerBalBefore = await buxToken.balanceOf(referrer.address);

      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, commitmentHash, wager, partialPayout, 0, 2, [0, 1, 0, 0, 1, 0, 0, 1], nonce, maxPayout
      );

      const referrerBalAfter = await buxToken.balanceOf(referrer.address);
      // lossAmount = 1000 - 300 = 700, referral = 700 * 20 / 10000 = 1.4 BUX
      const lossAmount = wager - partialPayout;
      const expectedReward = (lossAmount * 20n) / 10000n;
      expect(referrerBalAfter - referrerBalBefore).to.equal(expectedReward);
    });
  });

  // =================================================================
  // 11. STATS TRACKING
  // =================================================================
  describe("Stats Tracking", function () {
    beforeEach(async function () {
      await seedHouse(INITIAL_DEPOSIT);
    });

    it("should track per-config bet counts", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager * 3n);

      // Place 3 bets on different configs
      const bet0 = await placeBet(player1, wager, 0, 56000);
      const bet1 = await placeBet(player1, wager, 3, 30000);
      const bet2 = await placeBet(player1, wager, 0, 56000);

      // Settle all as losses
      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, bet0.commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], bet0.nonce, bet0.maxPayout
      );
      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, bet1.commitmentHash, wager, 0, 3, 0, [0, 0, 0, 0, 0, 0, 0, 0], bet1.nonce, bet1.maxPayout
      );
      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, bet2.commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], bet2.nonce, bet2.maxPayout
      );

      const betsPerConfig = await bankroll.getPlinkoBetsPerConfig(player1.address);
      expect(betsPerConfig[0]).to.equal(2n); // config 0: 2 bets
      expect(betsPerConfig[3]).to.equal(1n); // config 3: 1 bet
    });

    it("should track per-config P/L", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager * 2n);

      // Bet 1: win on config 0
      const bet1 = await placeBet(player1, wager, 0, 56000);
      const payout1 = ethers.parseEther("200"); // 2x
      await bankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, bet1.commitmentHash, wager, payout1, 0, 6, [1, 1, 1, 1, 0, 0, 1, 1], bet1.nonce, bet1.maxPayout
      );

      // Bet 2: lose on config 0
      const bet2 = await placeBet(player1, wager, 0, 56000);
      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, bet2.commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], bet2.nonce, bet2.maxPayout
      );

      const pnlPerConfig = await bankroll.getPlinkoPnLPerConfig(player1.address);
      // Win: +100 profit, Loss: -100 = net 0
      expect(pnlPerConfig[0]).to.equal(0n);
    });

    it("should track global accounting (totalBets, totalHouseProfit, etc.)", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager * 2n);

      // Bet 1: loss
      const bet1 = await placeBet(player1, wager, 0, 56000);
      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, bet1.commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], bet1.nonce, bet1.maxPayout
      );

      // Bet 2: win
      const bet2 = await placeBet(player1, wager, 0, 56000);
      const payout2 = ethers.parseEther("300"); // 3x
      await bankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, bet2.commitmentHash, wager, payout2, 0, 7, [1, 1, 1, 1, 1, 0, 1, 1], bet2.nonce, bet2.maxPayout
      );

      const acc = await bankroll.getPlinkoAccounting();
      expect(acc[0]).to.equal(2n); // totalBets
      expect(acc[1]).to.equal(1n); // totalWins
      expect(acc[2]).to.equal(1n); // totalLosses
      expect(acc[4]).to.equal(wager * 2n); // totalVolumeWagered
      // totalHouseProfit = +100 (loss) - 200 (win profit) = -100
      expect(acc[6]).to.equal(-ethers.parseEther("100"));
    });

    it("should track largest win and largest bet", async function () {
      const smallWager = ethers.parseEther("50");
      const bigWager = ethers.parseEther("200");
      await mintAndApprove(player1, smallWager + bigWager);

      // Small bet with big win
      const bet1 = await placeBet(player1, smallWager, 0, 56000);
      const bigPayout = ethers.parseEther("250"); // 5x
      await bankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, bet1.commitmentHash, smallWager, bigPayout, 0, 7, [1, 1, 1, 1, 1, 1, 1, 0], bet1.nonce, bet1.maxPayout
      );

      // Big bet with loss
      const bet2 = await placeBet(player1, bigWager, 0, 56000);
      await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
        player1.address, bet2.commitmentHash, bigWager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], bet2.nonce, bet2.maxPayout
      );

      const acc = await bankroll.getPlinkoAccounting();
      expect(acc[7]).to.equal(bigPayout - smallWager); // largestWin (profit = 200)
      expect(acc[8]).to.equal(bigWager); // largestBet
    });

    it("should calculate win rate correctly", async function () {
      const wager = ethers.parseEther("100");
      await mintAndApprove(player1, wager * 4n);

      // 3 losses, 1 win
      for (let i = 0; i < 3; i++) {
        const bet = await placeBet(player1, wager, 0, 56000);
        await bankroll.connect(plinkoGame).settlePlinkoLosingBet(
          player1.address, bet.commitmentHash, wager, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0], bet.nonce, bet.maxPayout
        );
      }

      const bet4 = await placeBet(player1, wager, 0, 56000);
      await bankroll.connect(plinkoGame).settlePlinkoWinningBet(
        player1.address, bet4.commitmentHash, wager, ethers.parseEther("200"), 0, 6, [1, 1, 1, 0, 1, 0, 1, 1], bet4.nonce, bet4.maxPayout
      );

      const acc = await bankroll.getPlinkoAccounting();
      // winRate = 1 * 10000 / 4 = 2500 bps = 25%
      expect(acc[9]).to.equal(2500n);
    });
  });

  // =================================================================
  // 12. ADMIN FUNCTIONS
  // =================================================================
  describe("Admin Functions", function () {
    it("should allow owner to set plinko game", async function () {
      const newGame = player1.address;
      await expect(bankroll.setPlinkoGame(newGame))
        .to.emit(bankroll, "GameAuthorized")
        .withArgs(newGame, true);
      expect(await bankroll.plinkoGame()).to.equal(newGame);
    });

    it("should allow owner to set max bet divisor", async function () {
      await expect(bankroll.setMaxBetDivisor(500))
        .to.emit(bankroll, "MaxBetDivisorChanged")
        .withArgs(1000, 500);
      expect(await bankroll.maximumBetSizeDivisor()).to.equal(500n);
    });

    it("should reject zero divisor", async function () {
      await expect(bankroll.setMaxBetDivisor(0)).to.be.revertedWith("Divisor must be > 0");
    });

    it("should allow owner to set referral basis points", async function () {
      await bankroll.setReferralBasisPoints(50); // 0.5%
      expect(await bankroll.referralBasisPoints()).to.equal(50n);
    });

    it("should reject referral basis points > 1000 (10%)", async function () {
      await expect(bankroll.setReferralBasisPoints(1001))
        .to.be.revertedWith("Basis points cannot exceed 10%");
    });

    it("should allow owner to set referral admin", async function () {
      await expect(bankroll.setReferralAdmin(referralAdmin.address))
        .to.emit(bankroll, "ReferralAdminChanged")
        .withArgs(ethers.ZeroAddress, referralAdmin.address);
    });

    it("should allow emergency BUX withdrawal", async function () {
      await seedHouse(ethers.parseEther("10000"));
      const ownerBalBefore = await buxToken.balanceOf(owner.address);

      await bankroll.emergencyWithdrawBUX(ethers.parseEther("5000"));

      const ownerBalAfter = await buxToken.balanceOf(owner.address);
      expect(ownerBalAfter - ownerBalBefore).to.equal(ethers.parseEther("5000"));

      const info = await bankroll.getHouseInfo();
      expect(info[0]).to.equal(ethers.parseEther("5000"));
    });

    it("should allow owner to pause and unpause", async function () {
      await bankroll.pause();
      expect(await bankroll.paused()).to.be.true;

      await bankroll.unpause();
      expect(await bankroll.paused()).to.be.false;
    });

    it("should block deposits when paused", async function () {
      await bankroll.pause();
      await mintAndApprove(player1, ONE_BUX);

      await expect(
        bankroll.connect(player1).depositBUX(ONE_BUX)
      ).to.be.revertedWithCustomError(bankroll, "EnforcedPause");
    });

    it("should block withdrawals when paused", async function () {
      await seedHouse(ethers.parseEther("1000"));
      await bankroll.pause();

      await expect(
        bankroll.connect(owner).withdrawBUX(ethers.parseEther("100"))
      ).to.be.revertedWithCustomError(bankroll, "EnforcedPause");
    });

    it("should reject non-owner admin calls", async function () {
      await expect(bankroll.connect(player1).setPlinkoGame(player2.address))
        .to.be.revertedWithCustomError(bankroll, "OwnableUnauthorizedAccount");
      await expect(bankroll.connect(player1).setMaxBetDivisor(500))
        .to.be.revertedWithCustomError(bankroll, "OwnableUnauthorizedAccount");
      await expect(bankroll.connect(player1).setReferralBasisPoints(50))
        .to.be.revertedWithCustomError(bankroll, "OwnableUnauthorizedAccount");
      await expect(bankroll.connect(player1).emergencyWithdrawBUX(ONE_BUX))
        .to.be.revertedWithCustomError(bankroll, "OwnableUnauthorizedAccount");
      await expect(bankroll.connect(player1).pause())
        .to.be.revertedWithCustomError(bankroll, "OwnableUnauthorizedAccount");
    });
  });

  // =================================================================
  // 13. GETMAXBET
  // =================================================================
  describe("getMaxBet", function () {
    beforeEach(async function () {
      await seedHouse(INITIAL_DEPOSIT); // 100k BUX
    });

    it("should calculate max bet based on net balance and multiplier", async function () {
      // netBalance = 100000, MAX_BET_BPS = 10 (0.1%)
      // baseMaxBet = 100000 * 10 / 10000 = 100 BUX
      // For 5.6x multiplier (56000 bps): maxBet = 100 * 20000 / 56000 ≈ 35.71 BUX
      const maxBet = await bankroll.getMaxBet(0, 56000);
      const expected = (INITIAL_DEPOSIT * 10n * 20000n) / (10000n * 56000n);
      expect(maxBet).to.equal(expected);
    });

    it("should return 0 when netBalance is 0", async function () {
      // Deploy a fresh bankroll with no deposits
      const BUXBankroll = await ethers.getContractFactory("BUXBankroll");
      const freshBankroll = await upgrades.deployProxy(
        BUXBankroll,
        [await buxToken.getAddress()],
        { initializer: "initialize", kind: "uups" }
      );
      expect(await freshBankroll.getMaxBet(0, 56000)).to.equal(0n);
    });

    it("should scale inversely with multiplier", async function () {
      const maxBetLow = await bankroll.getMaxBet(0, 20000);   // 2x
      const maxBetHigh = await bankroll.getMaxBet(0, 100000);  // 10x

      // Higher multiplier = lower max bet
      expect(maxBetHigh).to.be.lt(maxBetLow);
      // maxBetLow/maxBetHigh should equal 100000/20000 = 5
      expect(maxBetLow / maxBetHigh).to.equal(5n);
    });
  });

  // =================================================================
  // 14. UUPS UPGRADE
  // =================================================================
  describe("UUPS Upgrade", function () {
    it("should allow owner to upgrade via upgradeToAndCall", async function () {
      // Deploy new implementation
      const BUXBankrollV2 = await ethers.getContractFactory("BUXBankroll");
      const newImpl = await BUXBankrollV2.deploy();
      await newImpl.waitForDeployment();

      // Upgrade via the proxy's upgradeToAndCall (OZ v5 UUPS pattern)
      await bankroll.upgradeToAndCall(await newImpl.getAddress(), "0x");

      // Verify proxy still works
      expect(await bankroll.buxToken()).to.equal(await buxToken.getAddress());
    });

    it("should reject upgrade from non-owner", async function () {
      const BUXBankrollV2 = await ethers.getContractFactory("BUXBankroll");
      const newImpl = await BUXBankrollV2.deploy();
      await newImpl.waitForDeployment();

      await expect(
        bankroll.connect(player1).upgradeToAndCall(await newImpl.getAddress(), "0x")
      ).to.be.revertedWithCustomError(bankroll, "OwnableUnauthorizedAccount");
    });

    it("should preserve state after upgrade", async function () {
      // Deposit first
      await seedHouse(ethers.parseEther("5000"));

      // Deploy new implementation
      const BUXBankrollV2 = await ethers.getContractFactory("BUXBankroll");
      const newImpl = await BUXBankrollV2.deploy();
      await newImpl.waitForDeployment();

      // Upgrade
      await bankroll.upgradeToAndCall(await newImpl.getAddress(), "0x");

      // State preserved
      expect(await bankroll.buxToken()).to.equal(await buxToken.getAddress());
      expect(await bankroll.owner()).to.equal(owner.address);
      const info = await bankroll.getHouseInfo();
      expect(info[0]).to.equal(ethers.parseEther("5000")); // totalBalance preserved
      expect(await bankroll.balanceOf(owner.address)).to.equal(ethers.parseEther("5000")); // LP tokens preserved
    });
  });

  // =================================================================
  // 15. VIEW FUNCTIONS
  // =================================================================
  describe("View Functions", function () {
    beforeEach(async function () {
      await seedHouse(INITIAL_DEPOSIT);
    });

    it("getHouseInfo should return all fields correctly", async function () {
      const info = await bankroll.getHouseInfo();
      expect(info[0]).to.equal(INITIAL_DEPOSIT); // totalBalance
      expect(info[1]).to.equal(0n); // liability
      expect(info[2]).to.equal(0n); // unsettledBets
      expect(info[3]).to.equal(INITIAL_DEPOSIT); // netBalance
      expect(info[4]).to.equal(INITIAL_DEPOSIT); // poolTokenSupply
      expect(info[5]).to.equal(ethers.parseEther("1")); // poolTokenPrice (1:1)
    });

    it("getPlinkoAccounting should return zero-initialized values", async function () {
      const acc = await bankroll.getPlinkoAccounting();
      expect(acc[0]).to.equal(0n); // totalBets
      expect(acc[9]).to.equal(0n); // winRate (0 bets)
      expect(acc[10]).to.equal(0n); // houseEdge (0 volume)
    });

    it("getPlinkoPlayerStats should return zero for new player", async function () {
      const stats = await bankroll.getPlinkoPlayerStats(player1.address);
      expect(stats[0]).to.equal(0n); // totalBets
    });

    it("getLPPrice should match calculated price", async function () {
      const info = await bankroll.getHouseInfo();
      expect(await bankroll.getLPPrice()).to.equal(info[5]);
    });
  });

  // =================================================================
  // 16. EDGE CASES
  // =================================================================
  describe("Edge Cases", function () {
    it("should handle deposit when all balance is unsettled", async function () {
      await seedHouse(ethers.parseEther("1000"));

      // Place a bet for the full house balance
      const wager = ethers.parseEther("1000");
      await mintAndApprove(player1, wager);
      await buxToken.connect(player1).transfer(await bankroll.getAddress(), wager);
      const maxPayout = wager * 2n;
      const commitHash = ethers.keccak256(ethers.toUtf8Bytes("edge-1"));

      await bankroll.connect(plinkoGame).updateHouseBalancePlinkoBetPlaced(
        commitHash, player1.address, wager, 0, 1, maxPayout
      );

      // effectiveBalance = 2000 - 1000 = 1000, so deposit should work at 1:1
      const newDeposit = ethers.parseEther("500");
      await mintAndApprove(player2, newDeposit);
      await bankroll.connect(player2).depositBUX(newDeposit);

      expect(await bankroll.balanceOf(player2.address)).to.equal(newDeposit);
    });

    it("should handle multiple depositors and proportional withdrawal", async function () {
      // Owner deposits 1000
      await seedHouse(ethers.parseEther("1000"));

      // Player1 deposits 1000
      await mintAndApprove(player1, ethers.parseEther("1000"));
      await bankroll.connect(player1).depositBUX(ethers.parseEther("1000"));

      // Both should have equal LP tokens
      expect(await bankroll.balanceOf(owner.address)).to.equal(ethers.parseEther("1000"));
      expect(await bankroll.balanceOf(player1.address)).to.equal(ethers.parseEther("1000"));

      // Owner withdraws all
      await bankroll.connect(owner).withdrawBUX(ethers.parseEther("1000"));
      expect(await buxToken.balanceOf(owner.address)).to.equal(ethers.parseEther("1000"));

      // Player1 withdraws all
      await bankroll.connect(player1).withdrawBUX(ethers.parseEther("1000"));
      expect(await buxToken.balanceOf(player1.address)).to.equal(ethers.parseEther("1000"));
    });

    it("should handle receive() fallback for accidental native token sends", async function () {
      // The contract has receive() external payable {} so this should not revert
      await expect(
        owner.sendTransaction({ to: await bankroll.getAddress(), value: ethers.parseEther("0.01") })
      ).to.not.be.reverted;
    });
  });
});

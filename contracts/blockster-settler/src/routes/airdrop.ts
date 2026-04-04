import { Router, Request, Response } from "express";
import { PublicKey, SystemProgram, LAMPORTS_PER_SOL } from "@solana/web3.js";
import {
  startRound,
  closeRound,
  drawWinners,
  fundPrizes,
  buildDepositBuxTx,
  buildClaimPrizeTx,
  getAirdropState,
  getRoundInfo,
  getCurrentRoundId,
} from "../services/airdrop-service";
import { BUX_DECIMALS } from "../config";

const router = Router();

// -------------------------------------------------------------------
// Authority Endpoints (settler wallet signs + sends)
// -------------------------------------------------------------------

/**
 * POST /airdrop-start-round
 * Body: { commitmentHash: string (hex), endTime: number (unix), prizeMint?: string }
 *
 * Starts a new airdrop round on-chain. Returns round ID and tx signature.
 */
router.post("/airdrop-start-round", async (req: Request, res: Response) => {
  try {
    const { commitmentHash, endTime, prizeMint } = req.body;

    if (!commitmentHash || !endTime) {
      return res.status(400).json({ error: "Missing commitmentHash or endTime" });
    }

    const hashBuf = Buffer.from(commitmentHash, "hex");
    if (hashBuf.length !== 32) {
      return res.status(400).json({ error: "commitmentHash must be 32 bytes (64 hex chars)" });
    }

    // Default to System Program (SOL prizes) if no prizeMint specified
    const mint = prizeMint
      ? new PublicKey(prizeMint)
      : SystemProgram.programId;

    const signature = await startRound(hashBuf, endTime, mint);

    // Read the new round ID
    const roundId = await getCurrentRoundId();

    res.json({
      roundId,
      transactionHash: signature,
    });
  } catch (error: any) {
    console.error("[airdrop-start-round] Error:", error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /airdrop-fund-prizes
 * Body: { roundId: number, amount: number, isSol?: boolean }
 *
 * Fund prizes for a round (SOL in lamport-denominated amount, or SPL raw amount).
 */
router.post("/airdrop-fund-prizes", async (req: Request, res: Response) => {
  try {
    const { roundId, amount, isSol } = req.body;

    if (roundId == null || amount == null) {
      return res.status(400).json({ error: "Missing roundId or amount" });
    }

    const isSolPrize = isSol !== false; // Default to SOL
    const rawAmount = isSolPrize
      ? BigInt(Math.floor(amount * LAMPORTS_PER_SOL))
      : BigInt(Math.floor(amount * 10 ** BUX_DECIMALS));

    const signature = await fundPrizes(roundId, rawAmount, isSolPrize);

    res.json({ transactionHash: signature });
  } catch (error: any) {
    console.error("[airdrop-fund-prizes] Error:", error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /airdrop-close
 * Body: { roundId: number }
 *
 * Closes an open round (captures slot at close).
 */
router.post("/airdrop-close", async (req: Request, res: Response) => {
  try {
    const { roundId } = req.body;

    if (roundId == null) {
      return res.status(400).json({ error: "Missing roundId" });
    }

    const signature = await closeRound(roundId);

    // Read the round info to get slot_at_close
    const roundInfo = await getRoundInfo(roundId);

    res.json({
      transactionHash: signature,
      slotAtClose: roundInfo?.slotAtClose ?? null,
    });
  } catch (error: any) {
    console.error("[airdrop-close] Error:", error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /airdrop-draw-winners
 * Body: { roundId: number, serverSeed: string (hex), winners: [{wallet, amount}] }
 *
 * Draws winners for a closed round.
 */
router.post("/airdrop-draw-winners", async (req: Request, res: Response) => {
  try {
    const { roundId, serverSeed, winners } = req.body;

    if (roundId == null || !serverSeed || !winners) {
      return res.status(400).json({ error: "Missing roundId, serverSeed, or winners" });
    }

    const seedBuf = Buffer.from(serverSeed, "hex");
    if (seedBuf.length !== 32) {
      return res.status(400).json({ error: "serverSeed must be 32 bytes (64 hex chars)" });
    }

    const winnerInfos = winners.map((w: any) => ({
      wallet: w.wallet,
      amount: BigInt(w.amount),
    }));

    const signature = await drawWinners(roundId, seedBuf, winnerInfos);

    res.json({ transactionHash: signature });
  } catch (error: any) {
    console.error("[airdrop-draw-winners] Error:", error.message);
    res.status(500).json({ error: error.message });
  }
});

// -------------------------------------------------------------------
// User Transaction Builders (returns unsigned tx for wallet signing)
// -------------------------------------------------------------------

/**
 * POST /airdrop-build-deposit
 * Body: { wallet: string, roundId: number, entryIndex: number, amount: number }
 *
 * Builds unsigned deposit BUX tx for user to sign with their wallet.
 */
router.post("/airdrop-build-deposit", async (req: Request, res: Response) => {
  try {
    const { wallet, roundId, entryIndex, amount } = req.body;

    if (!wallet || roundId == null || entryIndex == null || amount == null) {
      return res.status(400).json({ error: "Missing wallet, roundId, entryIndex, or amount" });
    }

    const transaction = await buildDepositBuxTx(wallet, roundId, entryIndex, amount);

    res.json({ transaction });
  } catch (error: any) {
    console.error("[airdrop-build-deposit] Error:", error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /airdrop-build-claim
 * Body: { wallet: string, roundId: number, winnerIndex: number }
 *
 * Builds unsigned claim prize tx for winner to sign with their wallet.
 */
router.post("/airdrop-build-claim", async (req: Request, res: Response) => {
  try {
    const { wallet, roundId, winnerIndex } = req.body;

    if (!wallet || roundId == null || winnerIndex == null) {
      return res.status(400).json({ error: "Missing wallet, roundId, or winnerIndex" });
    }

    const transaction = await buildClaimPrizeTx(wallet, roundId, winnerIndex);

    res.json({ transaction });
  } catch (error: any) {
    console.error("[airdrop-build-claim] Error:", error.message);
    res.status(500).json({ error: error.message });
  }
});

// -------------------------------------------------------------------
// Read-Only Endpoints
// -------------------------------------------------------------------

/**
 * GET /airdrop-vault-round-id
 *
 * Returns the current round ID from on-chain state.
 */
router.get("/airdrop-vault-round-id", async (_req: Request, res: Response) => {
  try {
    const roundId = await getCurrentRoundId();
    res.json({ roundId });
  } catch (error: any) {
    console.error("[airdrop-vault-round-id] Error:", error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /airdrop-round-info/:roundId
 *
 * Returns full on-chain round state.
 */
router.get("/airdrop-round-info/:roundId", async (req: Request, res: Response) => {
  try {
    const roundId = parseInt(req.params.roundId as string, 10);
    if (isNaN(roundId)) {
      return res.status(400).json({ error: "Invalid roundId" });
    }

    const roundInfo = await getRoundInfo(roundId);
    if (!roundInfo) {
      return res.status(404).json({ error: "Round not found" });
    }

    res.json(roundInfo);
  } catch (error: any) {
    console.error("[airdrop-round-info] Error:", error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /airdrop-state
 *
 * Returns the airdrop program state.
 */
router.get("/airdrop-state", async (_req: Request, res: Response) => {
  try {
    const state = await getAirdropState();
    if (!state) {
      return res.status(404).json({ error: "Airdrop program not initialized" });
    }
    res.json(state);
  } catch (error: any) {
    console.error("[airdrop-state] Error:", error.message);
    res.status(500).json({ error: error.message });
  }
});

export default router;

import { Router, Request, Response } from "express";
import { buildPlaceBetTx, buildReclaimExpiredTx } from "../services/bankroll-service";

const router = Router();

/**
 * POST /build-place-bet
 * Body: { wallet, gameId, nonce, amount, maxPayout, vaultType }
 *
 * Builds an unsigned place_bet transaction for user signing.
 * vaultType: "sol" or "bux"
 */
router.post("/build-place-bet", async (req: Request, res: Response) => {
  try {
    const { wallet, gameId, nonce, amount, maxPayout, vaultType } = req.body;

    if (!wallet || gameId === undefined || nonce === undefined || !amount || maxPayout === undefined || !vaultType) {
      return res.status(400).json({ error: "Missing required fields" });
    }

    if (vaultType !== "sol" && vaultType !== "bux") {
      return res.status(400).json({ error: "vaultType must be 'sol' or 'bux'" });
    }

    const tx = await buildPlaceBetTx(
      wallet,
      gameId,
      nonce,
      amount,
      maxPayout,
      vaultType as "sol" | "bux"
    );

    res.json({ transaction: tx, wallet, gameId, nonce, amount, maxPayout, vaultType });
  } catch (err: any) {
    console.error("Build tx error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /build-reclaim-expired
 * Body: { wallet, nonce, vaultType }
 *
 * Builds an unsigned reclaim_expired transaction for player signing.
 * Used to reclaim stuck bets that have exceeded the bet timeout.
 * vaultType: "sol" or "bux"
 */
router.post("/build-reclaim-expired", async (req: Request, res: Response) => {
  try {
    const { wallet, nonce, vaultType } = req.body;

    if (!wallet || nonce === undefined || !vaultType) {
      return res.status(400).json({ error: "Missing required fields: wallet, nonce, vaultType" });
    }

    if (vaultType !== "sol" && vaultType !== "bux") {
      return res.status(400).json({ error: "vaultType must be 'sol' or 'bux'" });
    }

    const tx = await buildReclaimExpiredTx(wallet, nonce, vaultType as "sol" | "bux");

    res.json({ transaction: tx, wallet, nonce, vaultType });
  } catch (err: any) {
    console.error("Build reclaim-expired tx error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;

import { Router, Request, Response } from "express";
import { mintBux } from "../services/token-service";

const router = Router();

/**
 * POST /mint
 * Body: { wallet, amount, userId, rewardType }
 *
 * Mints BUX SPL tokens to the specified wallet.
 */
router.post("/mint", async (req: Request, res: Response) => {
  try {
    const { wallet, amount, userId, rewardType } = req.body;

    if (!wallet || !amount) {
      return res.status(400).json({ error: "Missing wallet or amount" });
    }

    const numAmount = parseFloat(amount);
    if (isNaN(numAmount) || numAmount <= 0) {
      return res.status(400).json({ error: "Invalid amount" });
    }

    const { signature, ataCreated } = await mintBux(wallet, numAmount);

    console.log(
      `Minted ${numAmount} BUX to ${wallet} (user: ${userId}, type: ${rewardType}) — tx: ${signature}${ataCreated ? " [ATA created]" : ""}`
    );

    res.json({
      success: true,
      signature,
      ataCreated,
      amount: numAmount,
      wallet,
    });
  } catch (err: any) {
    // err.message can be empty for some web3.js error subclasses (e.g. when the
    // info is in .logs / .transactionMessage). Dump everything so it's actionable.
    const detail =
      err?.message ||
      err?.transactionMessage ||
      (err?.logs && Array.isArray(err.logs) ? err.logs.join(" | ") : "") ||
      String(err);
    console.error(`Mint error [${err?.constructor?.name || typeof err}]: ${detail}`);
    res.status(500).json({ error: detail });
  }
});

// NOTE: BUX burn for shop checkout happens client-side in
// assets/js/hooks/solana_bux_burn.js — the buyer signs an SPL BurnChecked
// instruction directly from their own ATA. The settler is NOT in the burn
// path. The previous /burn endpoint here was a non-functional stub that
// always returned success without doing anything on-chain; removed to avoid
// misleading future operators.

export default router;

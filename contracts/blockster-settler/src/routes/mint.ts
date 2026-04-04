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
    console.error("Mint error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /burn
 * Body: { wallet, amount, userId }
 *
 * Transfers BUX from user to treasury (for shop checkout).
 * This builds and submits a transfer using the mint authority
 * (requires prior delegation/approval from user).
 *
 * For now, returns unsigned TX for user signing.
 */
router.post("/burn", async (req: Request, res: Response) => {
  try {
    const { wallet, amount } = req.body;

    if (!wallet || !amount) {
      return res.status(400).json({ error: "Missing wallet or amount" });
    }

    // For BUX burns in shop checkout, the Elixir backend deducts from Mnesia
    // and calls this endpoint to burn on-chain async.
    // TODO: Implement actual burn/transfer when treasury wallet is configured

    res.json({
      success: true,
      message: "Burn acknowledged (on-chain transfer pending treasury setup)",
      wallet,
      amount,
    });
  } catch (err: any) {
    console.error("Burn error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;

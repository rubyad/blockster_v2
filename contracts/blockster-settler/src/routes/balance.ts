import { Router, Request, Response } from "express";
import { getBuxBalance, getSolBalance } from "../services/token-service";

const router = Router();

/**
 * GET /balance/:wallet
 *
 * Returns SOL and BUX balances for a wallet.
 */
router.get("/balance/:wallet", async (req: Request, res: Response) => {
  try {
    const wallet = req.params.wallet as string;

    const [sol, bux] = await Promise.all([
      getSolBalance(wallet),
      getBuxBalance(wallet),
    ]);

    res.json({
      wallet,
      sol,
      bux,
      solLamports: Math.round(sol * 1e9),
      buxRaw: Math.round(bux * 1e9),
    });
  } catch (err: any) {
    console.error("Balance error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /balances/:wallet
 *
 * Returns all token balances (currently just SOL + BUX).
 */
router.get("/balances/:wallet", async (req: Request, res: Response) => {
  try {
    const wallet = req.params.wallet as string;

    const [sol, bux] = await Promise.all([
      getSolBalance(wallet),
      getBuxBalance(wallet),
    ]);

    res.json({
      wallet,
      balances: {
        sol: { amount: sol, lamports: Math.round(sol * 1e9) },
        bux: { amount: bux, raw: Math.round(bux * 1e9) },
      },
    });
  } catch (err: any) {
    console.error("Balances error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;

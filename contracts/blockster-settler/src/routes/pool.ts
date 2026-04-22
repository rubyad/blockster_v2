import { Router, Request, Response } from "express";
import {
  getPoolStats,
  getGameConfig,
  buildDepositSolTx,
  buildWithdrawSolTx,
  buildDepositBuxTx,
  buildWithdrawBuxTx,
  getLpBalance,
} from "../services/bankroll-service";

const router = Router();

/**
 * GET /pool-stats
 *
 * Returns bankroll vault stats and LP prices.
 * Reads SolVaultState and BuxVaultState from on-chain.
 */
router.get("/pool-stats", async (_req: Request, res: Response) => {
  try {
    const stats = await getPoolStats();
    res.json(stats);
  } catch (err: any) {
    console.error("Pool stats error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /game-config/:gameId
 *
 * Returns game configuration (max bet, min bet, fee, house balance).
 */
router.get("/game-config/:gameId", async (req: Request, res: Response) => {
  try {
    const gameId = parseInt(req.params.gameId as string, 10);
    const config = await getGameConfig(gameId);
    res.json(config);
  } catch (err: any) {
    console.error("Game config error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /lp-balance/:wallet/:vaultType
 *
 * Returns LP token balance (bSOL or bBUX) for a wallet.
 */
router.get("/lp-balance/:wallet/:vaultType", async (req: Request, res: Response) => {
  try {
    const { wallet, vaultType } = req.params;
    if (vaultType !== "sol" && vaultType !== "bux") {
      return res.status(400).json({ error: "vaultType must be 'sol' or 'bux'" });
    }
    const balance = await getLpBalance(wallet as string, vaultType as "sol" | "bux");
    res.json({ wallet, vaultType, balance });
  } catch (err: any) {
    console.error("LP balance error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// Optional feePayerMode — "player" (default) or "settler" (Web3Auth).
// Anything else defaults to "player" for safety: Wallet Standard wallets
// (Phantom/Solflare/Backpack) reject txs where they aren't fee_payer, so
// we never implicitly relax to "settler" for unknown callers.
function parseFeePayerMode(raw: unknown): "player" | "settler" {
  return raw === "settler" ? "settler" : "player";
}

/**
 * POST /build-deposit-sol
 * Body: { wallet, amount, feePayerMode? }
 *
 * Builds unsigned deposit SOL transaction for user signing.
 */
router.post("/build-deposit-sol", async (req: Request, res: Response) => {
  try {
    const { wallet, amount, feePayerMode } = req.body;
    if (!wallet || !amount || amount <= 0) {
      return res.status(400).json({ error: "wallet and positive amount required" });
    }
    const mode = parseFeePayerMode(feePayerMode);
    const tx = await buildDepositSolTx(wallet, amount, mode);
    res.json({ transaction: tx, wallet, amount, feePayerMode: mode });
  } catch (err: any) {
    console.error("Build deposit SOL error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /build-withdraw-sol
 * Body: { wallet, lpAmount, feePayerMode? }
 *
 * Builds unsigned withdraw SOL transaction (burn bSOL).
 */
router.post("/build-withdraw-sol", async (req: Request, res: Response) => {
  try {
    const { wallet, lpAmount, feePayerMode } = req.body;
    if (!wallet || !lpAmount || lpAmount <= 0) {
      return res.status(400).json({ error: "wallet and positive lpAmount required" });
    }
    const mode = parseFeePayerMode(feePayerMode);
    const tx = await buildWithdrawSolTx(wallet, lpAmount, mode);
    res.json({ transaction: tx, wallet, lpAmount, feePayerMode: mode });
  } catch (err: any) {
    console.error("Build withdraw SOL error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /build-deposit-bux
 * Body: { wallet, amount, feePayerMode? }
 *
 * Builds unsigned deposit BUX transaction for user signing.
 */
router.post("/build-deposit-bux", async (req: Request, res: Response) => {
  try {
    const { wallet, amount, feePayerMode } = req.body;
    if (!wallet || !amount || amount <= 0) {
      return res.status(400).json({ error: "wallet and positive amount required" });
    }
    const mode = parseFeePayerMode(feePayerMode);
    const tx = await buildDepositBuxTx(wallet, amount, mode);
    res.json({ transaction: tx, wallet, amount, feePayerMode: mode });
  } catch (err: any) {
    console.error("Build deposit BUX error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /build-withdraw-bux
 * Body: { wallet, lpAmount, feePayerMode? }
 *
 * Builds unsigned withdraw BUX transaction (burn bBUX).
 */
router.post("/build-withdraw-bux", async (req: Request, res: Response) => {
  try {
    const { wallet, lpAmount, feePayerMode } = req.body;
    if (!wallet || !lpAmount || lpAmount <= 0) {
      return res.status(400).json({ error: "wallet and positive lpAmount required" });
    }
    const mode = parseFeePayerMode(feePayerMode);
    const tx = await buildWithdrawBuxTx(wallet, lpAmount, mode);
    res.json({ transaction: tx, wallet, lpAmount, feePayerMode: mode });
  } catch (err: any) {
    console.error("Build withdraw BUX error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;

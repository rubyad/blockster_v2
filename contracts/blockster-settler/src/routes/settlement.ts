import { Router, Request, Response } from "express";
import { settleBet } from "../services/bankroll-service";

const router = Router();

/**
 * POST /settle-bet
 * Body: { player, nonce, serverSeed, won, payout, vaultType }
 *
 * Settles a bet on the bankroll program by revealing the server seed.
 * Called by Elixir backend after game result is calculated.
 */
router.post("/settle-bet", async (req: Request, res: Response) => {
  try {
    const { player, nonce, serverSeed, won, payout, vaultType } = req.body;

    if (!player || nonce === undefined || !serverSeed || won === undefined) {
      return res.status(400).json({ error: "Missing required fields" });
    }

    const vault = vaultType || "bux";
    const signature = await settleBet(player, nonce, serverSeed, won, payout || 0, vault);

    console.log(
      `Bet settled for player ${player}, nonce ${nonce}, won: ${won}, payout: ${payout}, sig: ${signature}`
    );

    res.json({
      success: true,
      player,
      nonce,
      won,
      payout,
      signature,
    });
  } catch (err: any) {
    // Structured response for the CF-01 commitment mismatch case so Elixir
    // can route the bet to manual_review instead of retrying forever.
    if (err?.code === "COMMITMENT_MISMATCH") {
      console.warn(
        `[settle-bet] commitment_mismatch for ${req.body?.player}/${req.body?.nonce}: ${err.message}`
      );
      return res.status(409).json({
        success: false,
        error: "commitment_mismatch",
        message: err.message,
        onchain_commitment_hash: err.onchain_commitment_hash,
        computed_commitment_hash: err.computed_commitment_hash,
      });
    }
    console.error("Settlement error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;

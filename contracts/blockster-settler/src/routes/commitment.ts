import { Router, Request, Response } from "express";
import { submitCommitment } from "../services/bankroll-service";

const router = Router();

/**
 * POST /submit-commitment
 * Body: { player, nonce, commitmentHash }
 *
 * Submits a commitment hash (SHA256 of server seed) to the bankroll program.
 * Called by Elixir backend before a player places a bet.
 */
router.post("/submit-commitment", async (req: Request, res: Response) => {
  try {
    const { player, nonce, commitmentHash } = req.body;

    if (!player || nonce === undefined || !commitmentHash) {
      return res
        .status(400)
        .json({ error: "Missing player, nonce, or commitmentHash" });
    }

    const signature = await submitCommitment(player, nonce, commitmentHash);

    console.log(
      `Commitment submitted for player ${player}, nonce ${nonce}, sig: ${signature}`
    );

    res.json({
      success: true,
      player,
      nonce,
      signature,
    });
  } catch (err: any) {
    console.error("Commitment error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;

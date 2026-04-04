import { Router, Request, Response } from "express";
import { PublicKey } from "@solana/web3.js";
import { connection, BANKROLL_PROGRAM_ID } from "../config";

const router = Router();

/**
 * GET /player-state/:wallet
 *
 * Returns on-chain PlayerState for a wallet: nonce, pending_nonce, has_active_order.
 * Used by Elixir to sync nonce and detect stuck bets.
 */
router.get("/player-state/:wallet", async (req: Request, res: Response) => {
  try {
    const wallet = req.params.wallet;
    const player = new PublicKey(wallet);
    const [playerState] = PublicKey.findProgramAddressSync(
      [Buffer.from("player"), player.toBuffer()],
      BANKROLL_PROGRAM_ID
    );

    const acct = await connection.getAccountInfo(playerState);
    if (!acct) {
      // Player has never interacted with the bankroll program
      return res.json({
        exists: false,
        nonce: 0,
        pending_nonce: 0,
        has_active_order: false,
      });
    }

    const d = acct.data;
    // PlayerState layout: disc(8) + player(32) + pending_commitment(32) + pending_nonce(8) + nonce(8) + has_active_order(1)
    const pendingNonce = Number(d.readBigUInt64LE(72));
    const nonce = Number(d.readBigUInt64LE(80));
    const hasActiveOrder = d.readUInt8(88) === 1;

    res.json({
      exists: true,
      nonce,
      pending_nonce: pendingNonce,
      has_active_order: hasActiveOrder,
    });
  } catch (err: any) {
    console.error("Player state error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;

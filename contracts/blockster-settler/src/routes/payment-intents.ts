import { Router, Request, Response } from "express";
import { PublicKey } from "@solana/web3.js";
import {
  derivePaymentIntentKeypair,
  getPaymentIntentPubkey,
  getPaymentIntentStatus,
  sweepPaymentIntent,
} from "../services/payment-intent-service";

const router = Router();

/**
 * POST /intents
 * Body: { orderId: string }
 * Returns: { pubkey: string }
 *
 * Derives an ephemeral keypair for the order (HKDF-deterministic, no
 * storage) and returns its public address for the buyer to send SOL to.
 */
router.post("/intents", (req: Request, res: Response) => {
  try {
    const { orderId } = req.body;
    if (!orderId || typeof orderId !== "string") {
      return res.status(400).json({ error: "Missing orderId" });
    }
    const pubkey = getPaymentIntentPubkey(orderId);
    return res.json({ pubkey });
  } catch (err: any) {
    console.error("[intents] create error:", err.message);
    return res.status(500).json({ error: err.message });
  }
});

/**
 * GET /intents/:pubkey?expected=<lamports>
 * Returns: { balance_lamports, funded, funded_tx_sig }
 *
 * Pubkey is resolvable from the order_id (derived), but Elixir sends the
 * pubkey directly since that's what it already has stored on the intent row.
 */
router.get("/intents/:pubkey", async (req: Request, res: Response) => {
  try {
    const { pubkey } = req.params;
    const expected = parseInt(String(req.query.expected || "0"), 10);

    if (!pubkey) return res.status(400).json({ error: "Missing pubkey" });
    if (isNaN(expected) || expected <= 0) {
      return res.status(400).json({ error: "Missing or invalid expected" });
    }

    const status = await getPaymentIntentStatus(new PublicKey(pubkey), expected);
    return res.json(status);
  } catch (err: any) {
    console.error("[intents] status error:", err.message);
    return res.status(500).json({ error: err.message });
  }
});

/**
 * POST /intents/:pubkey/sweep
 * Body: { orderId: string }
 * Returns: { tx_sig: string }
 *
 * Sweeps the funded balance from the ephemeral pubkey to treasury. Caller
 * must provide orderId so we can re-derive the keypair; we verify the
 * derived pubkey matches the one in the path.
 */
router.post("/intents/:pubkey/sweep", async (req: Request, res: Response) => {
  try {
    const { pubkey } = req.params;
    const { orderId } = req.body || {};

    if (!pubkey) return res.status(400).json({ error: "Missing pubkey" });
    if (!orderId) return res.status(400).json({ error: "Missing orderId" });

    const derived = derivePaymentIntentKeypair(orderId).publicKey.toBase58();
    if (derived !== pubkey) {
      return res.status(400).json({ error: "orderId does not match pubkey" });
    }

    const sig = await sweepPaymentIntent(orderId);
    return res.json({ tx_sig: sig });
  } catch (err: any) {
    console.error("[intents] sweep error:", err.message);
    return res.status(500).json({ error: err.message });
  }
});

export default router;

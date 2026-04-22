import { Router, Request, Response } from "express";
import { PublicKey } from "@solana/web3.js";
import { connection, BANKROLL_PROGRAM_ID } from "../config";
import { deriveBetOrder } from "../services/bankroll-service";

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

/**
 * GET /pending-bets/:wallet?startNonce=X&count=N
 *
 * Scans on-chain for pending bet_order PDAs in the nonce range
 * [startNonce, startNonce+count). Returns all that exist with status=Pending.
 *
 * Used by Elixir's stuck-bet detector + mount reconciler — Mnesia can miss a
 * bet if a frontend error path fires before the "bet placed" event reaches
 * the LiveView. On-chain is the source of truth.
 *
 * Defaults: startNonce = max(0, player.nonce - 20), count = 20. We iterate
 * backwards from the current nonce because settled/reclaimed bets are
 * closed on-chain (getAccountInfo returns null for closed PDAs).
 *
 * BetOrder layout (147 bytes total):
 *   disc(8) + player(32) + game_id(8) + vault_type(1) + amount(8) +
 *   max_payout(8) + commitment_hash(32) + nonce(8) + status(1) +
 *   created_at(8) + bump(1) + rent_payer(32)
 *
 * BetOrderStatus: 0 = Pending, 1 = Settled, 2 = Expired
 */
router.get("/pending-bets/:wallet", async (req: Request, res: Response) => {
  try {
    const wallet = req.params.wallet;
    const player = new PublicKey(wallet);

    // Find current on-chain nonce to anchor the scan range
    const [playerState] = PublicKey.findProgramAddressSync(
      [Buffer.from("player"), player.toBuffer()],
      BANKROLL_PROGRAM_ID
    );
    const playerStateAcct = await connection.getAccountInfo(playerState);

    const currentNonce = playerStateAcct
      ? Number(playerStateAcct.data.readBigUInt64LE(80))
      : 0;

    const count = Math.min(
      Math.max(1, parseInt(String(req.query.count || "20"), 10) || 20),
      100
    );
    const defaultStart = Math.max(0, currentNonce - count);
    const startNonce = Math.max(
      0,
      parseInt(String(req.query.startNonce ?? defaultStart), 10)
    );

    // Derive PDAs for the scan range and batch-fetch.
    const nonceList: number[] = [];
    const pdas: PublicKey[] = [];
    for (let i = 0; i < count; i++) {
      const n = startNonce + i;
      if (n >= currentNonce && n > startNonce) break; // don't scan beyond current nonce
      nonceList.push(n);
      const [pda] = deriveBetOrder(player, BigInt(n));
      pdas.push(pda);
    }

    // getMultipleAccountsInfo caps at 100 keys per call; our count max is 100.
    const accounts = await connection.getMultipleAccountsInfo(pdas, "confirmed");

    const pendingBets: any[] = [];

    accounts.forEach((acct, idx) => {
      if (!acct) return; // closed or never existed
      if (acct.data.length < 147) return; // wrong account type

      const d = acct.data;
      const vaultType = d.readUInt8(48) === 0 ? "sol" : "bux";
      const amount = Number(d.readBigUInt64LE(49));
      // commitment_hash sits at offset 65 (disc 8 + player 32 + game_id 8 +
      // vault_type 1 + amount 8 + max_payout 8), 32 bytes. Serialised as
      // hex lowercase to match CoinFlipGame.init_game_with_nonce storage.
      const commitmentHashHex = Buffer.from(d.subarray(65, 97)).toString("hex");
      const nonce = Number(d.readBigUInt64LE(97));
      const status = d.readUInt8(105);
      const createdAt = Number(d.readBigInt64LE(106));
      const rentPayer = new PublicKey(d.subarray(115, 147)).toBase58();

      if (status !== 0) return; // only pending

      pendingBets.push({
        nonce,
        vault_type: vaultType,
        amount_raw: amount,
        amount: vaultType === "sol" ? amount / 1e9 : amount / 1e9,
        commitment_hash: commitmentHashHex,
        created_at: createdAt,
        rent_payer: rentPayer,
        bet_order_pda: pdas[idx].toBase58(),
      });
    });

    res.json({
      wallet,
      current_nonce: currentNonce,
      scanned_range: { start: startNonce, count: nonceList.length },
      pending_bets: pendingBets,
    });
  } catch (err: any) {
    console.error("Pending bets error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

export default router;

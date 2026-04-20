import express from "express";
import { PORT, SOLANA_NETWORK, SOLANA_RPC_URL, BUX_MINT_ADDRESS, MINT_AUTHORITY } from "./config";
import { hmacAuth } from "./middleware/hmac-auth";

// Routes
import mintRoutes from "./routes/mint";
import balanceRoutes from "./routes/balance";
import commitmentRoutes from "./routes/commitment";
import settlementRoutes from "./routes/settlement";
import poolRoutes from "./routes/pool";
import buildTxRoutes from "./routes/build-tx";
import airdropRoutes from "./routes/airdrop";
import playerStateRoutes from "./routes/player-state";
import paymentIntentRoutes from "./routes/payment-intents";

const app = express();

// Middleware
app.use(express.json());

// Health check (no auth)
app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    network: SOLANA_NETWORK,
    buxMint: BUX_MINT_ADDRESS.toBase58(),
    mintAuthority: MINT_AUTHORITY.publicKey.toBase58(),
  });
});

// Authenticated routes
app.use(hmacAuth);
app.use(mintRoutes);
app.use(balanceRoutes);
app.use(commitmentRoutes);
app.use(settlementRoutes);
app.use(poolRoutes);
app.use(buildTxRoutes);
app.use(airdropRoutes);
app.use(playerStateRoutes);
app.use(paymentIntentRoutes);

// Start server
app.listen(PORT, () => {
  console.log(`Blockster Settler running on port ${PORT}`);
  console.log(`Network: ${SOLANA_NETWORK}`);
  console.log(`RPC: ${SOLANA_RPC_URL}`);
  console.log(`BUX Mint: ${BUX_MINT_ADDRESS.toBase58()}`);
  console.log(`Mint Authority: ${MINT_AUTHORITY.publicKey.toBase58()}`);
});

export default app;

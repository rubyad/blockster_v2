require('dotenv').config();

const express = require('express');
const cors = require('cors');
const http = require('http');
const path = require('path');

const config = require('./config');
const DatabaseService = require('./services/database');
const ContractService = require('./services/contract');
const EventListener = require('./services/eventListener');
const OwnerSyncService = require('./services/ownerSync');
const WebSocketServer = require('./routes/websocket');
const createApiRoutes = require('./routes/api');

// NFT Revenue Sharing services
const PriceService = require('./services/priceService');
const RewardEventListener = require('./services/rewardEventListener');
const EarningsSyncService = require('./services/earningsSyncService');
const createRevenueRoutes = require('./routes/revenues');

// Time-based rewards (Phase 3)
const TimeRewardTracker = require('./services/timeRewardTracker');
const adminTxQueue = require('./services/adminTxQueue');

// Initialize services
const db = new DatabaseService();
const contractService = new ContractService();

// Create Express app and HTTP server
const app = express();
const server = http.createServer(app);

// Initialize WebSocket server
const wsServer = new WebSocketServer(server);

// Initialize event listener (Arbitrum NFT events)
const eventListener = new EventListener(contractService, db, wsServer);

// Initialize owner sync service
const ownerSync = new OwnerSyncService(db, contractService);

// Initialize NFT Revenue Sharing services (Rogue Chain)
const priceService = new PriceService(wsServer, config);
const rewardEventListener = new RewardEventListener(db, wsServer, config);

// Initialize Time-based rewards tracker (Phase 3)
const timeRewardTracker = new TimeRewardTracker(db, adminTxQueue, wsServer);

// Initialize EarningsSyncService with TimeRewardTracker for combined stats
const earningsSyncService = new EarningsSyncService(db, priceService, config, wsServer, timeRewardTracker);

// Middleware
app.use(cors());
app.use(express.json());

// Serve static files from public directory
app.use(express.static(path.join(__dirname, '../public')));

// API routes
app.use('/api', createApiRoutes(db, contractService, ownerSync));

// Revenue sharing API routes
const revenueRouter = createRevenueRoutes(db, priceService);
revenueRouter.setTimeRewardTracker(timeRewardTracker);
app.use('/api/revenues', revenueRouter);

// Wire up TimeRewardTracker to EventListener for automatic tracking
eventListener.setTimeRewardTracker(timeRewardTracker);

// Handle client-side routing - serve index.html for all non-API routes
app.get('*', (req, res) => {
  if (!req.path.startsWith('/api')) {
    res.sendFile(path.join(__dirname, '../public/index.html'));
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('[Server] Error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
server.listen(config.PORT, () => {
  console.log(`[Server] High Rollers NFT server running on port ${config.PORT}`);
  console.log(`[Server] Contract: ${config.CONTRACT_ADDRESS}`);
  console.log(`[Server] Network: ${config.CHAIN_NAME} (Chain ID: ${config.CHAIN_ID})`);

  // Start background services (Arbitrum)
  eventListener.start();
  ownerSync.start();

  // Start NFT Revenue Sharing services (Rogue Chain)
  priceService.start();
  rewardEventListener.start();
  earningsSyncService.start();
});

// Graceful shutdown
function gracefulShutdown(signal) {
  console.log(`[Server] ${signal} received, shutting down...`);

  // Stop Arbitrum services
  eventListener.stop();
  ownerSync.stop();

  // Stop Rogue Chain services
  priceService.stop();
  rewardEventListener.stop();
  earningsSyncService.stop();

  // Close connections
  wsServer.close();
  db.close();

  server.close(() => {
    console.log('[Server] Server closed');
    process.exit(0);
  });
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

module.exports = { app, server };

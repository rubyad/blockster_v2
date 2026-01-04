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

// Initialize services
const db = new DatabaseService();
const contractService = new ContractService();

// Create Express app and HTTP server
const app = express();
const server = http.createServer(app);

// Initialize WebSocket server
const wsServer = new WebSocketServer(server);

// Initialize event listener
const eventListener = new EventListener(contractService, db, wsServer);

// Initialize owner sync service
const ownerSync = new OwnerSyncService(db, contractService);

// Middleware
app.use(cors());
app.use(express.json());

// Serve static files from public directory
app.use(express.static(path.join(__dirname, '../public')));

// API routes
app.use('/api', createApiRoutes(db, contractService, ownerSync));

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

  // Start background services
  eventListener.start();
  ownerSync.start();
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('[Server] SIGTERM received, shutting down...');
  eventListener.stop();
  ownerSync.stop();
  wsServer.close();
  db.close();
  server.close(() => {
    console.log('[Server] Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('[Server] SIGINT received, shutting down...');
  eventListener.stop();
  ownerSync.stop();
  wsServer.close();
  db.close();
  server.close(() => {
    console.log('[Server] Server closed');
    process.exit(0);
  });
});

module.exports = { app, server };

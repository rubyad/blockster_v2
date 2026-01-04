const WebSocket = require('ws');

class WebSocketServer {
  constructor(server) {
    this.wss = new WebSocket.Server({ server });
    this.clients = new Set();

    this.wss.on('connection', (ws, req) => {
      console.log('[WebSocket] Client connected');
      this.clients.add(ws);

      // Send welcome message
      ws.send(JSON.stringify({
        type: 'CONNECTED',
        data: { message: 'Connected to High Rollers NFT server' }
      }));

      ws.on('message', (message) => {
        try {
          const data = JSON.parse(message);
          this.handleMessage(ws, data);
        } catch (error) {
          console.error('[WebSocket] Invalid message:', error);
        }
      });

      ws.on('close', () => {
        console.log('[WebSocket] Client disconnected');
        this.clients.delete(ws);
      });

      ws.on('error', (error) => {
        console.error('[WebSocket] Client error:', error);
        this.clients.delete(ws);
      });

      // Ping to keep connection alive
      ws.isAlive = true;
      ws.on('pong', () => {
        ws.isAlive = true;
      });
    });

    // Heartbeat to detect dead connections
    this.heartbeatInterval = setInterval(() => {
      this.wss.clients.forEach((ws) => {
        if (ws.isAlive === false) {
          this.clients.delete(ws);
          return ws.terminate();
        }
        ws.isAlive = false;
        ws.ping();
      });
    }, 30000);

    console.log('[WebSocket] Server initialized');
  }

  handleMessage(ws, data) {
    switch (data.type) {
      case 'PING':
        ws.send(JSON.stringify({ type: 'PONG' }));
        break;

      case 'SUBSCRIBE':
        // Could implement channel subscriptions here
        ws.subscriptions = data.channels || [];
        break;

      default:
        console.log('[WebSocket] Unknown message type:', data.type);
    }
  }

  /**
   * Broadcast a message to all connected clients
   */
  broadcast(message) {
    const messageStr = JSON.stringify(message);
    let sent = 0;

    this.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(messageStr);
        sent++;
      }
    });

    if (sent > 0) {
      console.log(`[WebSocket] Broadcast ${message.type} to ${sent} clients`);
    }
  }

  /**
   * Send message to a specific client
   */
  sendTo(ws, message) {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message));
    }
  }

  /**
   * Broadcast to clients subscribed to a specific channel
   */
  broadcastToChannel(channel, message) {
    const messageStr = JSON.stringify(message);

    this.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN &&
          client.subscriptions?.includes(channel)) {
        client.send(messageStr);
      }
    });
  }

  /**
   * Get number of connected clients
   */
  getClientCount() {
    return this.clients.size;
  }

  /**
   * Close all connections and cleanup
   */
  close() {
    clearInterval(this.heartbeatInterval);
    this.wss.clients.forEach((client) => {
      client.close();
    });
    this.wss.close();
    console.log('[WebSocket] Server closed');
  }
}

module.exports = WebSocketServer;

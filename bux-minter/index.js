import express from 'express';
import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
app.use(express.json());

/**
 * TransactionQueue - Serializes blockchain transactions to prevent nonce conflicts
 *
 * Under concurrent load, multiple requests querying the provider for nonce will
 * get the same value (since previous tx hasn't mined yet). This queue ensures:
 * 1. Only one transaction processes at a time per wallet
 * 2. Nonce is tracked locally and incremented after each send
 * 3. Nonce errors trigger re-sync and retry with exponential backoff
 */
class TransactionQueue {
  constructor(wallet, provider, name) {
    this.wallet = wallet;
    this.provider = provider;
    this.name = name;
    this.queue = [];
    this.processing = false;
    this.currentNonce = null;
    this.nonceInitialized = false;
    this.maxRetries = 5;
    this.baseDelayMs = 100;
  }

  /**
   * Add a transaction to the queue
   * @param {Function} txFunction - Async function that takes (nonce) and returns tx receipt
   * @param {Object} options - Optional settings { priority: boolean }
   * @returns {Promise} - Resolves with tx receipt when transaction is mined
   */
  async enqueue(txFunction, options = {}) {
    return new Promise((resolve, reject) => {
      const item = {
        txFunction,
        resolve,
        reject,
        retries: 0,
        priority: options.priority || false,
        enqueuedAt: Date.now()
      };

      if (options.priority) {
        // Priority items go to front (after other priority items)
        const lastPriorityIndex = this.queue.findIndex(i => !i.priority);
        if (lastPriorityIndex === -1) {
          this.queue.push(item);
        } else {
          this.queue.splice(lastPriorityIndex, 0, item);
        }
      } else {
        this.queue.push(item);
      }

      console.log(`[TxQueue:${this.name}] Enqueued transaction (queue size: ${this.queue.length})`);
      this.processQueue();
    });
  }

  /**
   * Initialize nonce from the blockchain (only called once or on error recovery)
   */
  async initNonce() {
    try {
      // Use 'pending' to include unconfirmed transactions
      this.currentNonce = await this.provider.getTransactionCount(this.wallet.address, 'pending');
      this.nonceInitialized = true;
      console.log(`[TxQueue:${this.name}] Initialized nonce to ${this.currentNonce}`);
    } catch (error) {
      console.error(`[TxQueue:${this.name}] Failed to initialize nonce:`, error.message);
      throw error;
    }
  }

  /**
   * Re-sync nonce from blockchain (used after nonce errors)
   */
  async resyncNonce() {
    try {
      const networkNonce = await this.provider.getTransactionCount(this.wallet.address, 'pending');
      console.log(`[TxQueue:${this.name}] Re-synced nonce: local was ${this.currentNonce}, network is ${networkNonce}`);
      this.currentNonce = networkNonce;
    } catch (error) {
      console.error(`[TxQueue:${this.name}] Failed to re-sync nonce:`, error.message);
      // Keep current nonce and hope for the best
    }
  }

  /**
   * Check if an error is a nonce-related error
   */
  isNonceError(error) {
    const message = error.message?.toLowerCase() || '';
    const code = error.code?.toLowerCase() || '';

    return (
      message.includes('nonce') ||
      message.includes('replacement transaction underpriced') ||
      message.includes('already known') ||
      message.includes('transaction with same nonce') ||
      code === 'nonce_expired' ||
      code === 'replacement_underpriced'
    );
  }

  /**
   * Process the queue sequentially
   */
  async processQueue() {
    if (this.processing || this.queue.length === 0) {
      return;
    }

    this.processing = true;

    while (this.queue.length > 0) {
      const item = this.queue.shift();
      const waitTime = Date.now() - item.enqueuedAt;

      if (waitTime > 1000) {
        console.log(`[TxQueue:${this.name}] Processing transaction (waited ${waitTime}ms in queue)`);
      }

      try {
        // Initialize nonce on first transaction
        if (!this.nonceInitialized) {
          await this.initNonce();
        }

        // Get nonce for this transaction and increment immediately
        const nonceToUse = this.currentNonce;
        this.currentNonce++;

        console.log(`[TxQueue:${this.name}] Executing transaction with nonce ${nonceToUse}`);

        // Execute the transaction function with the nonce
        const receipt = await item.txFunction(nonceToUse);

        console.log(`[TxQueue:${this.name}] Transaction confirmed: ${receipt.hash}`);
        item.resolve(receipt);

      } catch (error) {
        console.error(`[TxQueue:${this.name}] Transaction failed:`, error.message);

        if (this.isNonceError(error) && item.retries < this.maxRetries) {
          // Nonce error - re-sync and retry
          item.retries++;
          const delay = this.baseDelayMs * Math.pow(2, item.retries - 1);

          console.log(`[TxQueue:${this.name}] Nonce error, retry ${item.retries}/${this.maxRetries} after ${delay}ms`);

          // Re-sync nonce from network
          await this.resyncNonce();

          // Wait before retry
          await new Promise(r => setTimeout(r, delay));

          // Put back at front of queue for immediate retry
          this.queue.unshift(item);

        } else {
          // Non-nonce error or max retries exceeded
          if (item.retries >= this.maxRetries) {
            console.error(`[TxQueue:${this.name}] Max retries exceeded, giving up`);
          }
          item.reject(error);
        }
      }

      // Small delay between transactions to avoid RPC rate limiting
      if (this.queue.length > 0) {
        await new Promise(r => setTimeout(r, 50));
      }
    }

    this.processing = false;
  }

  /**
   * Get queue status for monitoring
   */
  status() {
    return {
      name: this.name,
      walletAddress: this.wallet.address,
      queueLength: this.queue.length,
      processing: this.processing,
      currentNonce: this.currentNonce,
      nonceInitialized: this.nonceInitialized
    };
  }
}

// Token contract addresses - all deployed on Rogue Chain
// NOTE: Hub tokens (moonBUX, neoBUX, etc.) removed - only BUX remains for rewards
const TOKEN_CONTRACTS = {
  BUX: '0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8'
};

// Private keys for token owner (from environment)
// NOTE: Hub token private keys removed - only BUX remains
const TOKEN_PRIVATE_KEYS = {
  BUX: process.env.OWNER_PRIVATE_KEY
};

// Default token for backward compatibility
const DEFAULT_TOKEN = 'BUX';
const BUX_CONTRACT_ADDRESS = TOKEN_CONTRACTS.BUX;

// Minimal ABI for minting - only the mint function we need
const BUX_ABI = [
  'function mint(address to, uint256 amount) external',
  'function balanceOf(address account) external view returns (uint256)',
  'function decimals() external view returns (uint8)'
];

// NOTE: BalanceAggregator no longer needed - we fetch BUX balance directly from contract

// Configuration from environment
const RPC_URL = process.env.RPC_URL || 'https://rpc.roguechain.io/rpc';
const OWNER_PRIVATE_KEY = process.env.OWNER_PRIVATE_KEY;
const API_SECRET = process.env.API_SECRET;
const PORT = process.env.PORT || 3001;

// Validate required environment variables
if (!OWNER_PRIVATE_KEY) {
  console.error('ERROR: OWNER_PRIVATE_KEY environment variable is required');
  process.exit(1);
}

if (!API_SECRET) {
  console.error('ERROR: API_SECRET environment variable is required');
  process.exit(1);
}

// Set up provider
const provider = new ethers.JsonRpcProvider(RPC_URL);

// Create wallets for each token that has a private key configured
const tokenWallets = {};
const tokenContracts = {};

for (const [token, privateKey] of Object.entries(TOKEN_PRIVATE_KEYS)) {
  if (privateKey) {
    tokenWallets[token] = new ethers.Wallet(privateKey, provider);
    tokenContracts[token] = new ethers.Contract(TOKEN_CONTRACTS[token], BUX_ABI, tokenWallets[token]);
    console.log(`[INIT] Configured ${token} with wallet ${tokenWallets[token].address}`);
  }
}

// Default wallet and contract for backward compatibility
const wallet = new ethers.Wallet(OWNER_PRIVATE_KEY, provider);
const buxContract = tokenContracts.BUX || new ethers.Contract(BUX_CONTRACT_ADDRESS, BUX_ABI, wallet);

// Helper function to get contract for a token
function getContractForToken(token) {
  const tokenName = token || DEFAULT_TOKEN;

  // Check if we have a configured contract for this token
  if (tokenContracts[tokenName]) {
    return { contract: tokenContracts[tokenName], wallet: tokenWallets[tokenName], token: tokenName };
  }

  // Fallback to default BUX contract
  console.log(`[WARN] No private key configured for ${tokenName}, falling back to BUX`);
  return { contract: buxContract, wallet: wallet, token: 'BUX' };
}

// Helper to check if a token is valid
function isValidToken(token) {
  return !token || TOKEN_CONTRACTS.hasOwnProperty(token);
}

// Authentication middleware - only accepts requests from the Blockster app
function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid authorization header' });
  }

  const token = authHeader.split(' ')[1];

  if (token !== API_SECRET) {
    return res.status(403).json({ error: 'Invalid API secret' });
  }

  next();
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', contract: BUX_CONTRACT_ADDRESS });
});

// Mint tokens endpoint - supports multiple token types
app.post('/mint', authenticate, async (req, res) => {
  const { walletAddress, amount, userId, postId, token } = req.body;

  // Validate input
  if (!walletAddress) {
    return res.status(400).json({ error: 'walletAddress is required' });
  }

  if (!amount || amount <= 0) {
    return res.status(400).json({ error: 'amount must be a positive number' });
  }

  // Validate wallet address format
  if (!ethers.isAddress(walletAddress)) {
    return res.status(400).json({ error: 'Invalid wallet address format' });
  }

  // Validate token if provided
  if (!isValidToken(token)) {
    return res.status(400).json({ error: `Invalid token: ${token}. Valid tokens: ${Object.keys(TOKEN_CONTRACTS).join(', ')}` });
  }

  // Get the appropriate contract for this token
  const { contract, wallet: tokenWallet, token: actualToken } = getContractForToken(token);

  // Get the minter queue
  const queue = txQueues.minter;
  if (!queue) {
    return res.status(503).json({ error: 'Transaction queue not initialized' });
  }

  try {
    // Get decimals (all tokens have 18 decimals like standard ERC20)
    const decimals = await contract.decimals();

    // Convert amount to wei (with proper decimals)
    const amountInWei = ethers.parseUnits(amount.toString(), decimals);

    // Execute mint transaction through queue
    const receipt = await queue.enqueue(async (nonce) => {
      console.log(`[/mint] Minting ${amount} ${actualToken} to ${walletAddress} with nonce ${nonce}`);
      const tx = await contract.mint(walletAddress, amountInWei, { nonce });
      return await tx.wait();
    });

    // Get new balance for this token
    const newBalance = await contract.balanceOf(walletAddress);
    const formattedBalance = ethers.formatUnits(newBalance, decimals);

    res.json({
      success: true,
      transactionHash: receipt.hash,
      blockNumber: receipt.blockNumber,
      walletAddress,
      amountMinted: amount,
      token: actualToken,
      newBalance: formattedBalance,
      userId,
      postId
    });

  } catch (error) {
    console.error(`[MINT] Error minting ${actualToken} tokens:`, error);

    // Return appropriate error response
    if (error.code === 'INSUFFICIENT_FUNDS') {
      return res.status(500).json({ error: `Insufficient gas funds in ${actualToken} minter wallet` });
    }

    if (error.reason) {
      return res.status(500).json({ error: `Contract error: ${error.reason}` });
    }

    res.status(500).json({ error: `Failed to mint ${actualToken} tokens`, details: error.message });
  }
});

// Get balance endpoint - supports optional token query parameter
app.get('/balance/:address', authenticate, async (req, res) => {
  const { address } = req.params;
  const { token } = req.query;

  if (!ethers.isAddress(address)) {
    return res.status(400).json({ error: 'Invalid wallet address format' });
  }

  // Validate token if provided
  if (!isValidToken(token)) {
    return res.status(400).json({ error: `Invalid token: ${token}. Valid tokens: ${Object.keys(TOKEN_CONTRACTS).join(', ')}` });
  }

  // Get the appropriate contract for this token
  const { contract, token: actualToken } = getContractForToken(token);

  try {
    const decimals = await contract.decimals();
    const balance = await contract.balanceOf(address);
    const formattedBalance = ethers.formatUnits(balance, decimals);

    res.json({
      address,
      token: actualToken,
      balance: formattedBalance,
      balanceWei: balance.toString()
    });
  } catch (error) {
    console.error(`[BALANCE] Error getting ${actualToken} balance:`, error);
    res.status(500).json({ error: `Failed to get ${actualToken} balance`, details: error.message });
  }
});

// Get all token balances for an address
app.get('/balances/:address', authenticate, async (req, res) => {
  const { address } = req.params;

  if (!ethers.isAddress(address)) {
    return res.status(400).json({ error: 'Invalid wallet address format' });
  }

  try {
    const balances = {};

    // Fetch balance for each configured token
    for (const [tokenName, contract] of Object.entries(tokenContracts)) {
      try {
        const decimals = await contract.decimals();
        const balance = await contract.balanceOf(address);
        balances[tokenName] = ethers.formatUnits(balance, decimals);
      } catch (err) {
        console.error(`[BALANCES] Error getting ${tokenName} balance:`, err.message);
        balances[tokenName] = '0';
      }
    }

    res.json({
      address,
      balances
    });
  } catch (error) {
    console.error(`[BALANCES] Error getting balances:`, error);
    res.status(500).json({ error: 'Failed to get balances', details: error.message });
  }
});

// Get BUX and ROGUE balances
// NOTE: Simplified - hub tokens removed, only BUX + ROGUE remain
app.get('/aggregated-balances/:address', authenticate, async (req, res) => {
  const { address } = req.params;

  if (!ethers.isAddress(address)) {
    return res.status(400).json({ error: 'Invalid wallet address format' });
  }

  try {

    // Fetch ROGUE (native token) balance using provider.getBalance()
    const rogueBalanceWei = await provider.getBalance(address);
    const rogueBalance = parseFloat(ethers.formatUnits(rogueBalanceWei, 18));

    // Fetch BUX balance directly from contract (simpler than using aggregator for single token)
    const buxBalance = await buxContract.balanceOf(address);
    const buxFormatted = parseFloat(ethers.formatUnits(buxBalance, 18));

    const balances = {
      ROGUE: rogueBalance,
      BUX: buxFormatted
    };

    res.json({
      address,
      balances
    });
  } catch (error) {
    console.error(`[BALANCES] Error getting balances:`, error);
    res.status(500).json({ error: 'Failed to get balances', details: error.message });
  }
});

// ============================================================
// BuxBoosterGame Contract Integration
// ============================================================

const BUXBOOSTER_CONTRACT_ADDRESS = '0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B';
const SETTLER_PRIVATE_KEY = process.env.SETTLER_PRIVATE_KEY;
const CONTRACT_OWNER_PRIVATE_KEY = process.env.CONTRACT_OWNER_PRIVATE_KEY;
const REFERRAL_ADMIN_BB_PRIVATE_KEY = process.env.REFERRAL_ADMIN_BB_PRIVATE_KEY;
const REFERRAL_ADMIN_RB_PRIVATE_KEY = process.env.REFERRAL_ADMIN_RB_PRIVATE_KEY;

// BuxBoosterGame ABI - only the functions we need
const BUXBOOSTER_ABI = [
  'function submitCommitment(bytes32 commitmentHash, address player, uint256 nonce) external',
  'function settleBet(bytes32 commitmentHash, bytes32 serverSeed, uint8[] results, bool won) external returns (uint256 payout)',
  'function settleBetROGUE(bytes32 commitmentHash, bytes32 serverSeed, uint8[] results, bool won) external returns (uint256 payout)',
  'function bets(bytes32 betId) external view returns (address player, address token, uint256 amount, int8 difficulty, bytes32 commitmentHash, uint256 nonce, uint256 timestamp, uint8 status)',
  'function configureToken(address token, bool enabled) external',
  'function depositHouseBalance(address token, uint256 amount) external',
  'function tokenConfigs(address) external view returns (bool enabled, uint256 houseBalance)',
  'function getPlayerCurrentCommitment(address player) external view returns (bytes32 commitmentHash, uint256 nonce, uint256 timestamp, bool used)',
  'function playerNonces(address player) external view returns (uint256)',
  'function ROGUE_TOKEN() external view returns (address)',
  'function setPlayerReferrer(address player, address referrer) external',
  'function playerReferrers(address player) external view returns (address)',
  'event BetSettled(bytes32 indexed commitmentHash, bool won, uint8[] results, uint256 payout, bytes32 serverSeed)',
  'event BetDetails(bytes32 indexed commitmentHash, address indexed token, uint256 amount, int8 difficulty, uint8[] predictions, uint256 nonce, uint256 timestamp)'
];

// Settler wallet for BuxBoosterGame (submits commitments and settlements)
let settlerWallet = null;
let buxBoosterContract = null;
let contractOwnerWallet = null;

if (SETTLER_PRIVATE_KEY) {
  settlerWallet = new ethers.Wallet(SETTLER_PRIVATE_KEY, provider);
  buxBoosterContract = new ethers.Contract(BUXBOOSTER_CONTRACT_ADDRESS, BUXBOOSTER_ABI, settlerWallet);
  console.log(`[INIT] BuxBoosterGame settler wallet: ${settlerWallet.address}`);
} else {
  console.log(`[WARN] SETTLER_PRIVATE_KEY not set - BuxBoosterGame endpoints disabled`);
}

if (CONTRACT_OWNER_PRIVATE_KEY) {
  contractOwnerWallet = new ethers.Wallet(CONTRACT_OWNER_PRIVATE_KEY, provider);
  console.log(`[INIT] BuxBoosterGame contract owner: ${contractOwnerWallet.address}`);
} else {
  console.log(`[WARN] CONTRACT_OWNER_PRIVATE_KEY not set - deposit endpoint disabled`);
}

// ============================================================
// ROGUEBankroll Contract Integration (for ROGUE betting)
// ============================================================

const ROGUE_BANKROLL_ADDRESS = '0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd';

// ROGUEBankroll ABI - only the functions we need
const ROGUE_BANKROLL_ABI = [
  'function getHouseInfo() external view returns (uint256 netBalance, uint256 totalBalance, uint256 minBetSize, uint256 maxBetSize)',
  'function setPlayerReferrer(address player, address referrer) external',
  'function playerReferrers(address player) external view returns (address)'
];

// ROGUEBankroll contract instance (read-only, no wallet needed)
const rogueBankrollContract = new ethers.Contract(ROGUE_BANKROLL_ADDRESS, ROGUE_BANKROLL_ABI, provider);
console.log(`[INIT] ROGUEBankroll contract: ${ROGUE_BANKROLL_ADDRESS}`);

// Referral admin wallets (separate from contract owner - can only call setPlayerReferrer)
let referralAdminBBWallet = null;
let referralAdminRBWallet = null;

if (REFERRAL_ADMIN_BB_PRIVATE_KEY) {
  referralAdminBBWallet = new ethers.Wallet(REFERRAL_ADMIN_BB_PRIVATE_KEY, provider);
  console.log(`[INIT] BuxBoosterGame referral admin: ${referralAdminBBWallet.address}`);
} else {
  console.log(`[WARN] REFERRAL_ADMIN_BB_PRIVATE_KEY not set - BuxBoosterGame referral endpoint disabled`);
}

if (REFERRAL_ADMIN_RB_PRIVATE_KEY) {
  referralAdminRBWallet = new ethers.Wallet(REFERRAL_ADMIN_RB_PRIVATE_KEY, provider);
  console.log(`[INIT] ROGUEBankroll referral admin: ${referralAdminRBWallet.address}`);
} else {
  console.log(`[WARN] REFERRAL_ADMIN_RB_PRIVATE_KEY not set - ROGUEBankroll referral endpoint disabled`);
}

// ROGUEBankroll writable contract instance (for setPlayerReferrer - requires referral admin wallet)
let rogueBankrollWriteContract = null;
if (referralAdminRBWallet) {
  rogueBankrollWriteContract = new ethers.Contract(ROGUE_BANKROLL_ADDRESS, ROGUE_BANKROLL_ABI, referralAdminRBWallet);
  console.log(`[INIT] ROGUEBankroll write contract configured with referral admin wallet`);
}

// BuxBoosterGame writable contract instance (for setPlayerReferrer - requires referral admin wallet)
let buxBoosterReferralContract = null;
if (referralAdminBBWallet) {
  buxBoosterReferralContract = new ethers.Contract(BUXBOOSTER_CONTRACT_ADDRESS, BUXBOOSTER_ABI, referralAdminBBWallet);
  console.log(`[INIT] BuxBoosterGame referral contract configured`);
}

// ============================================================
// ROGUE Sender Wallet (for reward/bonus ROGUE transfers)
// ============================================================

const ROGUE_SENDER_PRIVATE_KEY = process.env.ROGUE_SENDER_PRIVATE_KEY;
let rogueSenderWallet = null;

if (ROGUE_SENDER_PRIVATE_KEY) {
  rogueSenderWallet = new ethers.Wallet(ROGUE_SENDER_PRIVATE_KEY, provider);
  console.log(`[INIT] ROGUE sender wallet: ${rogueSenderWallet.address}`);
} else {
  console.log(`[WARN] ROGUE_SENDER_PRIVATE_KEY not set - /transfer-rogue endpoint disabled`);
}

// ============================================================
// Transaction Queues - One per wallet to serialize transactions
// ============================================================

const txQueues = {};

// Create queue for minter wallet
if (wallet) {
  txQueues.minter = new TransactionQueue(wallet, provider, 'minter');
  console.log(`[INIT] Transaction queue created for minter wallet: ${wallet.address}`);
}

// Create queue for settler wallet
if (settlerWallet) {
  txQueues.settler = new TransactionQueue(settlerWallet, provider, 'settler');
  console.log(`[INIT] Transaction queue created for settler wallet: ${settlerWallet.address}`);
}

// Create queue for contract owner wallet
if (contractOwnerWallet) {
  txQueues.contractOwner = new TransactionQueue(contractOwnerWallet, provider, 'contractOwner');
  console.log(`[INIT] Transaction queue created for contract owner wallet: ${contractOwnerWallet.address}`);
}

// Create queue for referral admin BB wallet
if (referralAdminBBWallet) {
  txQueues.referralBB = new TransactionQueue(referralAdminBBWallet, provider, 'referralBB');
  console.log(`[INIT] Transaction queue created for referral admin BB wallet: ${referralAdminBBWallet.address}`);
}

// Create queue for referral admin RB wallet
if (referralAdminRBWallet) {
  txQueues.referralRB = new TransactionQueue(referralAdminRBWallet, provider, 'referralRB');
  console.log(`[INIT] Transaction queue created for referral admin RB wallet: ${referralAdminRBWallet.address}`);
}

// Create queue for ROGUE sender wallet
if (rogueSenderWallet) {
  txQueues.rogueSender = new TransactionQueue(rogueSenderWallet, provider, 'rogueSender');
  console.log(`[INIT] Transaction queue created for ROGUE sender wallet: ${rogueSenderWallet.address}`);
}

// Submit commitment for a new game
// Called by Blockster server when player initiates a game
app.post('/submit-commitment', authenticate, async (req, res) => {
  if (!buxBoosterContract) {
    return res.status(503).json({ error: 'BuxBoosterGame not configured - SETTLER_PRIVATE_KEY missing' });
  }

  const { commitmentHash, player, nonce } = req.body;

  if (!commitmentHash || !player || nonce === undefined) {
    return res.status(400).json({ error: 'commitmentHash, player, and nonce are required' });
  }

  if (!ethers.isAddress(player)) {
    return res.status(400).json({ error: 'Invalid player address format' });
  }

  // Get the settler queue
  const queue = txQueues.settler;
  if (!queue) {
    return res.status(503).json({ error: 'Settler transaction queue not initialized' });
  }

  try {
    const receipt = await queue.enqueue(async (txNonce) => {
      console.log(`[/submit-commitment] Submitting commitment ${commitmentHash} for ${player} with tx nonce ${txNonce}`);
      const tx = await buxBoosterContract.submitCommitment(commitmentHash, player, nonce, { nonce: txNonce });
      return await tx.wait();
    });

    res.json({
      success: true,
      txHash: receipt.hash,
      blockNumber: receipt.blockNumber,
      commitmentHash,
      player,
      nonce
    });
  } catch (error) {
    console.error(`[COMMITMENT] Error:`, error);

    if (error.reason) {
      return res.status(400).json({ error: error.reason });
    }
    res.status(500).json({ error: 'Failed to submit commitment', details: error.message });
  }
});

// Settle a bet after the game animation completes
// Called by Blockster server with the revealed server seed and results
// V3: Server now sends results to contract instead of contract calculating them
app.post('/settle-bet', authenticate, async (req, res) => {
  if (!buxBoosterContract) {
    return res.status(503).json({ error: 'BuxBoosterGame not configured - SETTLER_PRIVATE_KEY missing' });
  }

  const { commitmentHash, serverSeed, results, won } = req.body;

  // Validate required fields
  if (!commitmentHash || !serverSeed || !results || won === undefined) {
    return res.status(400).json({ error: 'commitmentHash, serverSeed, results, and won are required' });
  }

  // Validate results is an array
  if (!Array.isArray(results)) {
    return res.status(400).json({ error: 'results must be an array' });
  }

  // Get the settler queue
  const queue = txQueues.settler;
  if (!queue) {
    return res.status(503).json({ error: 'Settler transaction queue not initialized' });
  }

  try {
    // Read bet info BEFORE queueing (this is a read call, no nonce needed)
    const bet = await buxBoosterContract.bets(commitmentHash);
    const isROGUE = bet.token === "0x0000000000000000000000000000000000000000";

    // Execute settlement through queue
    const receipt = await queue.enqueue(async (nonce) => {
      console.log(`[/settle-bet] Settling bet ${commitmentHash} (ROGUE: ${isROGUE}) with nonce ${nonce}`);

      const tx = isROGUE
        ? await buxBoosterContract.settleBetROGUE(commitmentHash, serverSeed, results, won, { nonce })
        : await buxBoosterContract.settleBet(commitmentHash, serverSeed, results, won, { nonce });

      return await tx.wait();
    });

    // Parse the BetSettled event to get the payout
    let payout = '0';
    for (const log of receipt.logs) {
      try {
        const parsed = buxBoosterContract.interface.parseLog(log);
        if (parsed && parsed.name === 'BetSettled') {
          payout = ethers.formatUnits(parsed.args.payout, 18);
          break;
        }
      } catch (e) {
        // Not our event, skip
      }
    }

    res.json({
      success: true,
      txHash: receipt.hash,
      blockNumber: receipt.blockNumber,
      commitmentHash,
      won,
      payout
    });
  } catch (error) {
    console.error(`[SETTLE] Error:`, error);

    // Handle specific contract errors
    if (error.message?.includes('0x05d09e5f')) {
      return res.status(400).json({ error: 'BetAlreadySettled', details: 'This bet has already been settled' });
    }
    if (error.message?.includes('0x469bfa91')) {
      return res.status(400).json({ error: 'BetNotFound', details: 'Bet not found on chain' });
    }
    if (error.reason) {
      return res.status(400).json({ error: error.reason });
    }
    res.status(500).json({ error: 'Failed to settle bet', details: error.message });
  }
});

// Deposit house balance for a token
// Called once per token to fund the house bankroll
app.post('/deposit-house-balance', authenticate, async (req, res) => {
  if (!contractOwnerWallet) {
    return res.status(503).json({ error: 'Contract owner not configured - CONTRACT_OWNER_PRIVATE_KEY missing' });
  }

  const { token, amount } = req.body;

  if (!token || !amount) {
    return res.status(400).json({ error: 'token and amount are required' });
  }

  const tokenAddress = TOKEN_CONTRACTS[token];
  if (!tokenAddress) {
    return res.status(400).json({ error: `Unknown token: ${token}` });
  }

  // Get the wallet that owns this token (has minting rights)
  const tokenWallet = tokenWallets[token];
  if (!tokenWallet) {
    return res.status(400).json({ error: `No wallet configured for ${token}` });
  }

  // Get transaction queues
  const tokenQueue = txQueues.minter;  // Token owner uses minter wallet
  const ownerQueue = txQueues.contractOwner;

  if (!tokenQueue || !ownerQueue) {
    return res.status(503).json({ error: 'Transaction queues not initialized' });
  }

  try {
    const amountWei = ethers.parseUnits(amount.toString(), 18);

    // Step 1: Mint tokens to the CONTRACT OWNER wallet (uses minter queue)
    console.log(`[/deposit-house-balance] Step 1: Minting ${amount} ${token} to contract owner`);
    const mintReceipt = await tokenQueue.enqueue(async (nonce) => {
      const tokenContract = tokenContracts[token];
      const tx = await tokenContract.mint(contractOwnerWallet.address, amountWei, { nonce });
      return await tx.wait();
    });
    console.log(`[/deposit-house-balance] Mint complete: ${mintReceipt.hash}`);

    // Step 2: Contract owner approves the BuxBoosterGame contract to spend tokens (uses contract owner queue)
    console.log(`[/deposit-house-balance] Step 2: Approving BuxBoosterGame to spend tokens`);
    const approveReceipt = await ownerQueue.enqueue(async (nonce) => {
      const erc20Abi = ['function approve(address spender, uint256 amount) external returns (bool)'];
      const tokenContractWithApprove = new ethers.Contract(tokenAddress, erc20Abi, contractOwnerWallet);
      const tx = await tokenContractWithApprove.approve(BUXBOOSTER_CONTRACT_ADDRESS, amountWei, { nonce });
      return await tx.wait();
    });
    console.log(`[/deposit-house-balance] Approve complete: ${approveReceipt.hash}`);

    // Step 3: Contract owner calls depositHouseBalance (uses contract owner queue)
    console.log(`[/deposit-house-balance] Step 3: Depositing to house balance`);
    const depositReceipt = await ownerQueue.enqueue(async (nonce) => {
      const buxBoosterFromOwner = new ethers.Contract(BUXBOOSTER_CONTRACT_ADDRESS, BUXBOOSTER_ABI, contractOwnerWallet);
      const tx = await buxBoosterFromOwner.depositHouseBalance(tokenAddress, amountWei, { nonce });
      return await tx.wait();
    });
    console.log(`[/deposit-house-balance] Deposit complete: ${depositReceipt.hash}`);

    // Get updated house balance
    const config = await buxBoosterContract.tokenConfigs(tokenAddress);

    res.json({
      success: true,
      mintTxHash: mintReceipt.hash,
      approveTxHash: approveReceipt.hash,
      depositTxHash: depositReceipt.hash,
      token,
      amountDeposited: amount,
      newHouseBalance: ethers.formatUnits(config.houseBalance, 18)
    });
  } catch (error) {
    console.error(`[DEPOSIT] Error:`, error);

    if (error.reason) {
      return res.status(400).json({ error: error.reason });
    }
    res.status(500).json({ error: 'Failed to deposit house balance', details: error.message });
  }
});

// Get player's on-chain nonce from BuxBoosterGame contract
// Fast endpoint that only queries playerNonces mapping
app.get('/player-nonce/:address', authenticate, async (req, res) => {
  if (!buxBoosterContract) {
    return res.status(503).json({ error: 'BuxBoosterGame not configured' });
  }

  const { address } = req.params;

  if (!ethers.isAddress(address)) {
    return res.status(400).json({ error: 'Invalid address format' });
  }

  try {
    // Query the playerNonces mapping directly (fastest query)
    const nonce = await buxBoosterContract.playerNonces(address);

    res.json({
      address,
      nonce: Number(nonce)
    });
  } catch (error) {
    console.error(`[PLAYER-NONCE] Error:`, error);
    res.status(500).json({ error: 'Failed to get player nonce', details: error.message });
  }
});

// Get player's current state from BuxBoosterGame contract
// Returns nonce and any unused commitment
app.get('/player-state/:address', authenticate, async (req, res) => {
  if (!buxBoosterContract) {
    return res.status(503).json({ error: 'BuxBoosterGame not configured' });
  }

  const { address } = req.params;

  if (!ethers.isAddress(address)) {
    return res.status(400).json({ error: 'Invalid address format' });
  }

  try {
    // Get current commitment state (includes nonce)
    const [commitmentHash, nonce, timestamp, used] = await buxBoosterContract.getPlayerCurrentCommitment(address);

    // Check if there's an unused commitment
    const hasUnusedCommitment = commitmentHash !== ethers.ZeroHash && !used;

    res.json({
      address,
      nonce: Number(nonce),
      commitmentHash: hasUnusedCommitment ? commitmentHash : null,
      commitmentTimestamp: hasUnusedCommitment ? Number(timestamp) : null,
      hasUnusedCommitment
    });
  } catch (error) {
    console.error(`[PLAYER-STATE] Error:`, error);
    res.status(500).json({ error: 'Failed to get player state', details: error.message });
  }
});

// Get token config from BuxBoosterGame
app.get('/game-token-config/:token', authenticate, async (req, res) => {
  if (!buxBoosterContract) {
    return res.status(503).json({ error: 'BuxBoosterGame not configured' });
  }

  const { token } = req.params;
  const tokenAddress = TOKEN_CONTRACTS[token];

  if (!tokenAddress) {
    return res.status(400).json({ error: `Unknown token: ${token}` });
  }

  try {
    const config = await buxBoosterContract.tokenConfigs(tokenAddress);

    // Handle null/undefined houseBalance
    const houseBalance = config.houseBalance && config.houseBalance.toString() !== '0'
      ? ethers.formatUnits(config.houseBalance, 18)
      : "0";

    res.json({
      token,
      tokenAddress,
      enabled: config.enabled || false,
      houseBalance: houseBalance
    });
  } catch (error) {
    console.error(`[CONFIG] Error querying ${token} at ${tokenAddress}:`, error);
    res.status(500).json({ error: 'Failed to get token config', details: error.message });
  }
});

// Get ROGUE house balance from ROGUEBankroll
app.get('/rogue-house-balance', authenticate, async (req, res) => {
  try {
    const [netBalance, totalBalance, minBetSize, maxBetSize] =
      await rogueBankrollContract.getHouseInfo();

    res.json({
      netBalance: ethers.formatEther(netBalance),
      totalBalance: ethers.formatEther(totalBalance),
      minBetSize: ethers.formatEther(minBetSize),
      maxBetSize: ethers.formatEther(maxBetSize)
    });
  } catch (error) {
    console.error('[ROGUE-HOUSE] Error fetching ROGUE house balance:', error);
    res.status(500).json({ error: 'Failed to get ROGUE house balance', details: error.message });
  }
});

// ============================================================
// Referral System - Set Player Referrer
// ============================================================

// Set a player's referrer on BOTH contracts (BuxBoosterGame for BUX bets, ROGUEBankroll for ROGUE bets)
// Called by Blockster server when a new user signs up with a referral code
app.post('/set-player-referrer', authenticate, async (req, res) => {
  if (!buxBoosterReferralContract || !rogueBankrollWriteContract) {
    return res.status(503).json({
      error: 'Referral system not configured - REFERRAL_ADMIN_BB_PRIVATE_KEY or REFERRAL_ADMIN_RB_PRIVATE_KEY missing'
    });
  }

  const { player, referrer } = req.body;

  // Validate input
  if (!player || !referrer) {
    return res.status(400).json({ error: 'player and referrer addresses are required' });
  }

  // Validate addresses
  if (!ethers.isAddress(player)) {
    return res.status(400).json({ error: 'Invalid player address' });
  }
  if (!ethers.isAddress(referrer)) {
    return res.status(400).json({ error: 'Invalid referrer address' });
  }

  // Normalize addresses
  const playerAddr = ethers.getAddress(player);
  const referrerAddr = ethers.getAddress(referrer);

  // Prevent self-referral
  if (playerAddr.toLowerCase() === referrerAddr.toLowerCase()) {
    return res.status(400).json({ error: 'Self-referral not allowed' });
  }

  // Get transaction queues
  const bbQueue = txQueues.referralBB;
  const rbQueue = txQueues.referralRB;

  if (!bbQueue || !rbQueue) {
    return res.status(503).json({ error: 'Referral transaction queues not initialized' });
  }

  const results = {
    buxBoosterGame: { success: false, txHash: null, error: null },
    rogueBankroll: { success: false, txHash: null, error: null }
  };

  // Check if referrers are already set (read operations - no queue needed)
  const [bbExistingReferrer, rbExistingReferrer] = await Promise.all([
    buxBoosterReferralContract.playerReferrers(playerAddr),
    rogueBankrollWriteContract.playerReferrers(playerAddr)
  ]);

  const bbAlreadySet = bbExistingReferrer !== ethers.ZeroAddress;
  const rbAlreadySet = rbExistingReferrer !== ethers.ZeroAddress;

  if (bbAlreadySet) {
    results.buxBoosterGame.error = 'Referrer already set';
  }
  if (rbAlreadySet) {
    results.rogueBankroll.error = 'Referrer already set';
  }

  // If both already set, return early
  if (bbAlreadySet && rbAlreadySet) {
    return res.status(409).json({
      error: 'Referrer already set on both contracts',
      results
    });
  }

  // Execute referrer updates in parallel (different wallets = different queues = safe to parallelize)
  const promises = [];

  if (!bbAlreadySet) {
    promises.push(
      bbQueue.enqueue(async (nonce) => {
        console.log(`[/set-player-referrer] Setting referrer on BuxBoosterGame with nonce ${nonce}`);
        const tx = await buxBoosterReferralContract.setPlayerReferrer(playerAddr, referrerAddr, { nonce });
        return await tx.wait();
      }).then(receipt => {
        results.buxBoosterGame.success = true;
        results.buxBoosterGame.txHash = receipt.hash;
      }).catch(error => {
        console.error(`[REFERRER] BuxBoosterGame error:`, error.message);
        results.buxBoosterGame.error = error.message;
      })
    );
  }

  if (!rbAlreadySet) {
    promises.push(
      rbQueue.enqueue(async (nonce) => {
        console.log(`[/set-player-referrer] Setting referrer on ROGUEBankroll with nonce ${nonce}`);
        const tx = await rogueBankrollWriteContract.setPlayerReferrer(playerAddr, referrerAddr, { nonce });
        return await tx.wait();
      }).then(receipt => {
        results.rogueBankroll.success = true;
        results.rogueBankroll.txHash = receipt.hash;
      }).catch(error => {
        console.error(`[REFERRER] ROGUEBankroll error:`, error.message);
        results.rogueBankroll.error = error.message;
      })
    );
  }

  // Wait for all queue operations to complete
  await Promise.all(promises);

  // Determine overall success
  const anySuccess = results.buxBoosterGame.success || results.rogueBankroll.success;

  res.json({
    success: anySuccess,
    player: playerAddr,
    referrer: referrerAddr,
    results
  });
});

// ============================================================
// ROGUE Transfer Endpoint - Send native ROGUE tokens
// ============================================================

app.post('/transfer-rogue', authenticate, async (req, res) => {
  if (!rogueSenderWallet) {
    return res.status(503).json({ error: 'ROGUE sender not configured - ROGUE_SENDER_PRIVATE_KEY missing' });
  }

  const { walletAddress, amount, userId, reason } = req.body;

  // Validate inputs
  if (!walletAddress) {
    return res.status(400).json({ error: 'walletAddress is required' });
  }

  if (!amount || amount <= 0) {
    return res.status(400).json({ error: 'amount must be a positive number' });
  }

  if (!ethers.isAddress(walletAddress)) {
    return res.status(400).json({ error: 'Invalid wallet address format' });
  }

  const queue = txQueues.rogueSender;
  if (!queue) {
    return res.status(503).json({ error: 'ROGUE sender transaction queue not initialized' });
  }

  try {
    const amountWei = ethers.parseEther(amount.toString());

    const receipt = await queue.enqueue(async (nonce) => {
      console.log(`[/transfer-rogue] Sending ${amount} ROGUE to ${walletAddress} (user: ${userId}, reason: ${reason}) with nonce ${nonce}`);
      const tx = await rogueSenderWallet.sendTransaction({
        to: walletAddress,
        value: amountWei,
        nonce
      });
      return await tx.wait();
    });

    res.json({
      success: true,
      transactionHash: receipt.hash,
      blockNumber: receipt.blockNumber,
      amount,
      walletAddress,
      userId,
      reason: reason || 'transfer'
    });
  } catch (error) {
    console.error(`[TRANSFER-ROGUE] Error:`, error);

    if (error.code === 'INSUFFICIENT_FUNDS') {
      return res.status(500).json({ error: 'Insufficient ROGUE balance in sender wallet' });
    }

    if (error.reason) {
      return res.status(400).json({ error: error.reason });
    }

    res.status(500).json({ error: 'Failed to transfer ROGUE', details: error.message });
  }
});

// ============================================================
// Queue Status Endpoint - For monitoring
// ============================================================

// Get status of all transaction queues
app.get('/queue-status', authenticate, (req, res) => {
  const status = {};

  for (const [name, queue] of Object.entries(txQueues)) {
    status[name] = queue.status();
  }

  res.json({
    timestamp: new Date().toISOString(),
    queues: status
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`BUX Minter service running on port ${PORT}`);
  console.log(`Contract address: ${BUX_CONTRACT_ADDRESS}`);
  console.log(`Minter wallet: ${wallet.address}`);
  if (buxBoosterContract) {
    console.log(`BuxBoosterGame: ${BUXBOOSTER_CONTRACT_ADDRESS}`);
    console.log(`Settler wallet: ${settlerWallet.address}`);
  }
  if (buxBoosterReferralContract && rogueBankrollWriteContract) {
    console.log(`Referral system: enabled`);
    console.log(`BuxBoosterGame referral admin: ${referralAdminBBWallet.address}`);
    console.log(`ROGUEBankroll referral admin: ${referralAdminRBWallet.address}`);
  }
});

import express from 'express';
import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
app.use(express.json());

// Token contract addresses - all deployed on Rogue Chain
const TOKEN_CONTRACTS = {
  BUX: '0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8',
  moonBUX: '0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5',
  neoBUX: '0x423656448374003C2cfEaFF88D5F64fb3A76487C',
  rogueBUX: '0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3',
  flareBUX: '0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8',
  nftBUX: '0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED',
  nolchaBUX: '0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642',
  solBUX: '0x92434779E281468611237d18AdE20A4f7F29DB38',
  spaceBUX: '0xAcaCa77FbC674728088f41f6d978F0194cf3d55A',
  tronBUX: '0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665',
  tranBUX: '0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96'
};

// Private keys for each token owner (from environment)
// Format: PRIVATE_KEY_TOKENNAME (e.g., PRIVATE_KEY_MOONBUX)
const TOKEN_PRIVATE_KEYS = {
  BUX: process.env.OWNER_PRIVATE_KEY,
  moonBUX: process.env.PRIVATE_KEY_MOONBUX,
  neoBUX: process.env.PRIVATE_KEY_NEOBUX,
  rogueBUX: process.env.PRIVATE_KEY_ROGUEBUX,
  flareBUX: process.env.PRIVATE_KEY_FLAREBUX,
  nftBUX: process.env.PRIVATE_KEY_NFTBUX,
  nolchaBUX: process.env.PRIVATE_KEY_NOLCHABUX,
  solBUX: process.env.PRIVATE_KEY_SOLBUX,
  spaceBUX: process.env.PRIVATE_KEY_SPACEBUX,
  tronBUX: process.env.PRIVATE_KEY_TRONBUX,
  tranBUX: process.env.PRIVATE_KEY_TRANBUX
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

// BalanceAggregator contract - fetches all token balances in a single call
const BALANCE_AGGREGATOR_ADDRESS = '0x3A5a60fE307088Ae3F367d529E601ac52ed2b660';
const BALANCE_AGGREGATOR_ABI = [
  'function getBalances(address user, address[] tokens) external view returns (uint256[] memory)'
];

// Token addresses array in the order we want balances returned
const TOKEN_ADDRESSES = Object.values(TOKEN_CONTRACTS);

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

  try {
    console.log(`[MINT] Starting mint: ${amount} ${actualToken} to ${walletAddress} (user: ${userId}, post: ${postId})`);

    // Get decimals (all tokens have 18 decimals like standard ERC20)
    const decimals = await contract.decimals();

    // Convert amount to wei (with proper decimals)
    const amountInWei = ethers.parseUnits(amount.toString(), decimals);

    // Execute mint transaction
    const tx = await contract.mint(walletAddress, amountInWei);
    console.log(`[MINT] Transaction submitted: ${tx.hash}`);

    // Wait for confirmation
    const receipt = await tx.wait();
    console.log(`[MINT] Transaction confirmed in block ${receipt.blockNumber}`);

    // Get new balance for this token
    const newBalance = await contract.balanceOf(walletAddress);
    const formattedBalance = ethers.formatUnits(newBalance, decimals);

    res.json({
      success: true,
      transactionHash: tx.hash,
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

// Token names in the order returned by BalanceAggregator.getBalances()
const TOKEN_ORDER = ['BUX', 'moonBUX', 'neoBUX', 'rogueBUX', 'flareBUX', 'nftBUX', 'nolchaBUX', 'solBUX', 'spaceBUX', 'tronBUX', 'tranBUX'];

// BalanceAggregator contract instance
const balanceAggregator = new ethers.Contract(BALANCE_AGGREGATOR_ADDRESS, BALANCE_AGGREGATOR_ABI, provider);

// Get all token balances via BalanceAggregator contract (single RPC call)
// Also fetches ROGUE (native token) balance separately
app.get('/aggregated-balances/:address', authenticate, async (req, res) => {
  const { address } = req.params;

  if (!ethers.isAddress(address)) {
    return res.status(400).json({ error: 'Invalid wallet address format' });
  }

  try {
    console.log(`[AGGREGATED] Fetching balances for ${address}`);

    // Fetch ROGUE (native token) balance using provider.getBalance()
    const rogueBalanceWei = await provider.getBalance(address);
    const rogueBalance = parseFloat(ethers.formatUnits(rogueBalanceWei, 18));

    // Call the aggregator contract - returns array of uint256 balances for ERC-20 tokens
    const rawBalances = await balanceAggregator.getBalances(address, TOKEN_ADDRESSES);

    // Convert to formatted balances map (all tokens have 18 decimals)
    const balances = { ROGUE: rogueBalance }; // Add ROGUE first
    let aggregate = 0;

    for (let i = 0; i < TOKEN_ORDER.length && i < rawBalances.length; i++) {
      const tokenName = TOKEN_ORDER[i];
      const formatted = parseFloat(ethers.formatUnits(rawBalances[i], 18));
      balances[tokenName] = formatted;
      aggregate += formatted; // Only BUX tokens count toward aggregate (not ROGUE)
    }

    console.log(`[AGGREGATED] Balances for ${address}: ROGUE=${rogueBalance}, aggregate=${aggregate}`);

    res.json({
      address,
      balances,
      aggregate
    });
  } catch (error) {
    console.error(`[AGGREGATED] Error getting balances:`, error);
    res.status(500).json({ error: 'Failed to get aggregated balances', details: error.message });
  }
});

// ============================================================
// BuxBoosterGame Contract Integration
// ============================================================

const BUXBOOSTER_CONTRACT_ADDRESS = '0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B';
const SETTLER_PRIVATE_KEY = process.env.SETTLER_PRIVATE_KEY;
const CONTRACT_OWNER_PRIVATE_KEY = process.env.CONTRACT_OWNER_PRIVATE_KEY;

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
  'function getHouseInfo() external view returns (uint256 netBalance, uint256 totalBalance, uint256 minBetSize, uint256 maxBetSize)'
];

// ROGUEBankroll contract instance (read-only, no wallet needed)
const rogueBankrollContract = new ethers.Contract(ROGUE_BANKROLL_ADDRESS, ROGUE_BANKROLL_ABI, provider);
console.log(`[INIT] ROGUEBankroll contract: ${ROGUE_BANKROLL_ADDRESS}`);

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

  try {
    console.log(`[COMMITMENT] Submitting commitment for player ${player}, nonce ${nonce}`);

    const tx = await buxBoosterContract.submitCommitment(commitmentHash, player, nonce);
    console.log(`[COMMITMENT] Transaction submitted: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log(`[COMMITMENT] Confirmed in block ${receipt.blockNumber}`);

    res.json({
      success: true,
      txHash: tx.hash,
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

  try {
    console.log(`[SETTLE] Settling bet ${commitmentHash}`);
    console.log(`[SETTLE] Results: ${results.join(',')}, Won: ${won}`);

    // V5: Check if this is a ROGUE bet and call the appropriate settlement function
    const bet = await buxBoosterContract.bets(commitmentHash);
    const isROGUE = bet.token === "0x0000000000000000000000000000000000000000";

    console.log(`[SETTLE] Bet token: ${bet.token}`);
    console.log(`[SETTLE] Is ROGUE bet: ${isROGUE}`);

    // Call the appropriate settlement function
    const tx = isROGUE
      ? await buxBoosterContract.settleBetROGUE(commitmentHash, serverSeed, results, won)
      : await buxBoosterContract.settleBet(commitmentHash, serverSeed, results, won);

    console.log(`[SETTLE] Transaction submitted: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log(`[SETTLE] Confirmed in block ${receipt.blockNumber}`);

    // Parse the BetSettled event to get the payout
    let payout = '0';
    for (const log of receipt.logs) {
      try {
        const parsed = buxBoosterContract.interface.parseLog(log);
        if (parsed && parsed.name === 'BetSettled') {
          payout = ethers.formatUnits(parsed.args.payout, 18);
          console.log(`[SETTLE] Payout: ${payout}`);
          break;
        }
      } catch (e) {
        // Not our event, skip
      }
    }

    res.json({
      success: true,
      txHash: tx.hash,
      blockNumber: receipt.blockNumber,
      commitmentHash,
      won,
      payout
    });
  } catch (error) {
    console.error(`[SETTLE] Error:`, error);

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

  try {
    const amountWei = ethers.parseUnits(amount.toString(), 18);
    console.log(`[DEPOSIT] Depositing ${amount} ${token} as house balance`);

    // Get starting nonces for both wallets
    let tokenOwnerNonce = await provider.getTransactionCount(tokenWallet.address, 'pending');
    let contractOwnerNonce = await provider.getTransactionCount(contractOwnerWallet.address, 'pending');
    console.log(`[DEPOSIT] Starting nonces - Token owner: ${tokenOwnerNonce}, Contract owner: ${contractOwnerNonce}`);

    // Step 1: Mint tokens to the CONTRACT OWNER wallet (not token owner)
    const tokenContract = tokenContracts[token];
    console.log(`[DEPOSIT] Minting ${amount} ${token} to contract owner ${contractOwnerWallet.address}`);
    const mintTx = await tokenContract.mint(contractOwnerWallet.address, amountWei, { nonce: tokenOwnerNonce++ });
    await mintTx.wait();
    console.log(`[DEPOSIT] Minted successfully`);

    // Step 2: Contract owner approves the BuxBoosterGame contract to spend tokens
    const erc20Abi = ['function approve(address spender, uint256 amount) external returns (bool)'];
    const tokenContractWithApprove = new ethers.Contract(tokenAddress, erc20Abi, contractOwnerWallet);
    console.log(`[DEPOSIT] Contract owner approving BuxBoosterGame contract`);
    const approveTx = await tokenContractWithApprove.approve(BUXBOOSTER_CONTRACT_ADDRESS, amountWei, { nonce: contractOwnerNonce++ });
    await approveTx.wait();
    console.log(`[DEPOSIT] Approved successfully`);

    // Step 3: Contract owner calls depositHouseBalance (onlyOwner function)
    const buxBoosterFromOwner = new ethers.Contract(BUXBOOSTER_CONTRACT_ADDRESS, BUXBOOSTER_ABI, contractOwnerWallet);
    console.log(`[DEPOSIT] Contract owner calling depositHouseBalance`);
    const depositTx = await buxBoosterFromOwner.depositHouseBalance(tokenAddress, amountWei, { nonce: contractOwnerNonce++ });
    const receipt = await depositTx.wait();
    console.log(`[DEPOSIT] Deposited ${amount} ${token} in block ${receipt.blockNumber}`);

    // Get updated house balance
    const config = await buxBoosterContract.tokenConfigs(tokenAddress);

    res.json({
      success: true,
      txHash: depositTx.hash,
      blockNumber: receipt.blockNumber,
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

    console.log(`[PLAYER-NONCE] Player ${address}: nonce=${nonce}`);

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

    console.log(`[PLAYER-STATE] Player ${address}: nonce=${nonce}, commitment=${commitmentHash}, used=${used}`);

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
    console.log(`[CONFIG] Querying tokenConfigs for ${token} at ${tokenAddress}`);
    const config = await buxBoosterContract.tokenConfigs(tokenAddress);
    console.log(`[CONFIG] Raw config:`, config);
    console.log(`[CONFIG] houseBalance type:`, typeof config.houseBalance);
    console.log(`[CONFIG] houseBalance value:`, config.houseBalance);

    // Handle null/undefined houseBalance
    const houseBalance = config.houseBalance && config.houseBalance.toString() !== '0'
      ? ethers.formatUnits(config.houseBalance, 18)
      : "0";

    console.log(`[CONFIG] Formatted house balance: ${houseBalance}`);

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
    console.log('[ROGUE-HOUSE] Fetching house balance from ROGUEBankroll');

    const [netBalance, totalBalance, minBetSize, maxBetSize] =
      await rogueBankrollContract.getHouseInfo();

    console.log(`[ROGUE-HOUSE] Raw values: net=${netBalance}, total=${totalBalance}, min=${minBetSize}, max=${maxBetSize}`);

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

// Start server
app.listen(PORT, () => {
  console.log(`BUX Minter service running on port ${PORT}`);
  console.log(`Contract address: ${BUX_CONTRACT_ADDRESS}`);
  console.log(`Minter wallet: ${wallet.address}`);
  if (buxBoosterContract) {
    console.log(`BuxBoosterGame: ${BUXBOOSTER_CONTRACT_ADDRESS}`);
    console.log(`Settler wallet: ${settlerWallet.address}`);
  }
});

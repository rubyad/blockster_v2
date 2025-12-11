import express from 'express';
import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
app.use(express.json());

// BUX Token contract details
const BUX_CONTRACT_ADDRESS = '0xbe46C2A9C729768aE938bc62eaC51C7Ad560F18d';

// Minimal ABI for minting - only the mint function we need
const BUX_ABI = [
  'function mint(address to, uint256 amount) external',
  'function balanceOf(address account) external view returns (uint256)',
  'function decimals() external view returns (uint8)'
];

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

// Set up provider and wallet
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(OWNER_PRIVATE_KEY, provider);
const buxContract = new ethers.Contract(BUX_CONTRACT_ADDRESS, BUX_ABI, wallet);

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

// Mint BUX tokens endpoint
app.post('/mint', authenticate, async (req, res) => {
  const { walletAddress, amount, userId, postId } = req.body;

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

  try {
    console.log(`[MINT] Starting mint: ${amount} BUX to ${walletAddress} (user: ${userId}, post: ${postId})`);

    // Get decimals (BUX likely has 18 decimals like standard ERC20)
    const decimals = await buxContract.decimals();

    // Convert amount to wei (with proper decimals)
    const amountInWei = ethers.parseUnits(amount.toString(), decimals);

    // Execute mint transaction
    const tx = await buxContract.mint(walletAddress, amountInWei);
    console.log(`[MINT] Transaction submitted: ${tx.hash}`);

    // Wait for confirmation
    const receipt = await tx.wait();
    console.log(`[MINT] Transaction confirmed in block ${receipt.blockNumber}`);

    // Get new balance
    const newBalance = await buxContract.balanceOf(walletAddress);
    const formattedBalance = ethers.formatUnits(newBalance, decimals);

    res.json({
      success: true,
      transactionHash: tx.hash,
      blockNumber: receipt.blockNumber,
      walletAddress,
      amountMinted: amount,
      newBalance: formattedBalance,
      userId,
      postId
    });

  } catch (error) {
    console.error(`[MINT] Error minting tokens:`, error);

    // Return appropriate error response
    if (error.code === 'INSUFFICIENT_FUNDS') {
      return res.status(500).json({ error: 'Insufficient gas funds in minter wallet' });
    }

    if (error.reason) {
      return res.status(500).json({ error: `Contract error: ${error.reason}` });
    }

    res.status(500).json({ error: 'Failed to mint tokens', details: error.message });
  }
});

// Get balance endpoint
app.get('/balance/:address', authenticate, async (req, res) => {
  const { address } = req.params;

  if (!ethers.isAddress(address)) {
    return res.status(400).json({ error: 'Invalid wallet address format' });
  }

  try {
    const decimals = await buxContract.decimals();
    const balance = await buxContract.balanceOf(address);
    const formattedBalance = ethers.formatUnits(balance, decimals);

    res.json({
      address,
      balance: formattedBalance,
      balanceWei: balance.toString()
    });
  } catch (error) {
    console.error(`[BALANCE] Error getting balance:`, error);
    res.status(500).json({ error: 'Failed to get balance', details: error.message });
  }
});

// Start server
app.listen(PORT, () => {
  console.log(`BUX Minter service running on port ${PORT}`);
  console.log(`Contract address: ${BUX_CONTRACT_ADDRESS}`);
  console.log(`Minter wallet: ${wallet.address}`);
});

import express from 'express';
import { ethers } from 'ethers';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
app.use(express.json());

// Token contract addresses - all deployed on Rogue Chain
const TOKEN_CONTRACTS = {
  BUX: '0xbe46C2A9C729768aE938bc62eaC51C7Ad560F18d',
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

// Start server
app.listen(PORT, () => {
  console.log(`BUX Minter service running on port ${PORT}`);
  console.log(`Contract address: ${BUX_CONTRACT_ADDRESS}`);
  console.log(`Minter wallet: ${wallet.address}`);
});

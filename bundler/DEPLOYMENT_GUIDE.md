# Rundler Bundler Deployment Guide for Fly.io

This guide will help you deploy the Rundler bundler for Rogue Chain testnet on Fly.io.

## Prerequisites

1. Fly.io account (sign up at https://fly.io)
2. Flyctl CLI installed (`curl -L https://fly.io/install.sh | sh`)
3. Private key with testnet ROGUE tokens (for paying gas)

## Step 1: Generate or Use Existing Private Key

You need a private key for the bundler to sign and submit transactions. This account must have testnet ROGUE tokens.

**Option A - Generate new private key** (using Node.js):
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

**Option B - Export from MetaMask**:
1. Open MetaMask
2. Click the three dots → Account details → Export Private Key
3. Enter your password
4. Copy the private key (without 0x prefix)

## Step 2: Fund the Bundler Account

1. Get the address from your private key:
   ```bash
   # Using cast (from Foundry)
   cast wallet address --private-key YOUR_PRIVATE_KEY

   # Or use an online tool (be careful with real funds!)
   # https://www.myetherwallet.com/wallet/access/software?type=privateKey
   ```

2. Send testnet ROGUE to this address:
   - Visit Rogue Chain testnet faucet
   - Send at least 10-100 testnet ROGUE to the bundler address
   - Verify balance on https://testnet-explorer.roguechain.io/

## Step 3: Deploy to Fly.io

Navigate to the bundler directory:
```bash
cd /Users/tenmerry/Projects/blockster_v2/bundler
```

### 3.1 Login to Fly.io
```bash
flyctl auth login
```

### 3.2 Create the App
```bash
flyctl apps create rogue-bundler
```

### 3.3 Set the Private Key Secret

**IMPORTANT**: Never commit your private key to git!

```bash
# Set the bundler private key (without 0x prefix)
flyctl secrets set BUILDER_PRIVATE_KEY=your_private_key_here -a rogue-bundler
```

### 3.4 Deploy the Bundler
```bash
flyctl deploy -a rogue-bundler
```

This will:
- Build the Docker image (takes ~10-15 minutes first time)
- Deploy to Fly.io
- Start the bundler service

### 3.5 Monitor the Deployment
```bash
# Watch deployment status
flyctl status -a rogue-bundler

# View logs
flyctl logs -a rogue-bundler

# Check if bundler is running
flyctl ssh console -a rogue-bundler -C "ps aux | grep rundler"
```

## Step 4: Verify Bundler is Working

### 4.1 Get the Bundler URL
```bash
flyctl info -a rogue-bundler
```

The bundler will be accessible at: `https://rogue-bundler.fly.dev`

### 4.2 Test the Bundler

```bash
# Test eth_supportedEntryPoints
curl -X POST https://rogue-bundler.fly.dev \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "eth_supportedEntryPoints",
    "params": []
  }'

# Expected response:
# {"jsonrpc":"2.0","id":1,"result":["0x71A862536cc591db628Dc45B063658042350176b"]}
```

### 4.3 Check Health
```bash
curl https://rogue-bundler.fly.dev/health
```

## Step 5: Update Blockster V2 App

Once the bundler is deployed and working, update your app configuration.

Edit `/Users/tenmerry/Projects/blockster_v2/assets/js/home_hooks.js`:

```javascript
// Line 164: Update bundlerUrl
bundlerUrl: "https://rogue-bundler.fly.dev",

// Line 167-171: Uncomment paymaster configuration
paymaster: async (userOp) => {
  return {
    paymasterAndData: paymasterAddress,
  };
},

// Line 173: Enable gas sponsorship
sponsorGas: true,
```

## Step 6: Test the Integration

1. Start your Phoenix server:
   ```bash
   cd /Users/tenmerry/Projects/blockster_v2
   mix phx.server
   ```

2. Visit http://localhost:4000

3. Log in with email

4. Click the "Test Paymaster" button (bottom-right corner)

5. The transaction should succeed with gas sponsored by the paymaster!

## Monitoring and Maintenance

### View Logs
```bash
# Stream logs
flyctl logs -a rogue-bundler --follow

# View last 100 lines
flyctl logs -a rogue-bundler --lines 100
```

### Check Bundler Balance
```bash
# SSH into the container
flyctl ssh console -a rogue-bundler

# Check balance (you'll need to install curl in container)
curl -X POST https://testnet-rpc.roguechain.io \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "eth_getBalance",
    "params": ["YOUR_BUNDLER_ADDRESS", "latest"]
  }'
```

### Restart Bundler
```bash
flyctl apps restart rogue-bundler
```

### Scale Resources (if needed)
```bash
# Increase memory
flyctl scale memory 4096 -a rogue-bundler

# Add more CPUs
flyctl scale vm shared-cpu-2x -a rogue-bundler
```

## Troubleshooting

### Bundler won't start
- Check logs: `flyctl logs -a rogue-bundler`
- Verify private key is set: `flyctl secrets list -a rogue-bundler`
- Ensure RPC is accessible: `curl https://testnet-rpc.roguechain.io`

### "Insufficient funds" errors
- Check bundler account balance on explorer
- Send more testnet ROGUE to bundler address
- Verify paymaster is funded

### Can't connect to bundler
- Verify app is running: `flyctl status -a rogue-bundler`
- Check firewall/CORS settings
- Test with curl from command line first

### High gas costs
- Monitor bundler spending
- Adjust `max_bundle_gas` in config
- Consider adjusting bundle interval

## Production Deployment

For mainnet deployment:

1. Update `bundler-config.toml`:
   - Change chain_id to 560013
   - Update RPC to `https://rpc.roguechain.io/rpc`
   - Update entry_point to mainnet address

2. Create new app:
   ```bash
   flyctl apps create rogue-bundler-mainnet
   ```

3. Use different private key with mainnet ROGUE

4. Update app configuration to use mainnet bundler URL

## Security Notes

- ✅ Private key is stored as Fly.io secret (encrypted)
- ✅ Never commit private keys to git
- ✅ Use separate accounts for testnet/mainnet
- ✅ Monitor bundler spending regularly
- ✅ Set up balance alerts
- ⚠️ Keep bundler account funded
- ⚠️ Rotate private keys periodically

## Cost Estimate

Fly.io pricing (approximate):
- Shared CPU 2x (2GB RAM): ~$12/month
- Bundler will spend ROGUE for gas (reimbursed by paymaster)
- Network egress: minimal

## Support

- Rundler documentation: https://github.com/alchemyplatform/rundler
- Fly.io docs: https://fly.io/docs/
- Blockster V2 issues: Check console logs and error messages

---

**Status**: Ready to deploy
**Next Step**: Follow Step 1 to generate/get your private key and fund it with testnet ROGUE

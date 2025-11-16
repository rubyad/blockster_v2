# Rundler Bundler for Rogue Chain

ERC-4337 Account Abstraction bundler service for Rogue Chain testnet.

## Quick Start

Follow the complete deployment guide in [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md).

## Files

- `Dockerfile` - Multi-stage build for Rundler
- `bundler-config.toml` - Rundler configuration for Rogue Chain
- `fly.toml` - Fly.io deployment configuration
- `DEPLOYMENT_GUIDE.md` - Complete step-by-step deployment instructions
- `.gitignore` - Prevents committing secrets

## What This Does

This bundler:
1. Accepts UserOperations from Blockster V2 app
2. Validates and simulates transactions
3. Bundles multiple UserOperations together
4. Submits bundles to Rogue Chain via EntryPoint contract
5. Enables gasless transactions via paymaster sponsorship

## Configuration

- **Chain ID**: 71499284269 (Rogue Chain Testnet)
- **EntryPoint**: 0x71A862536cc591db628Dc45B063658042350176b
- **Paymaster**: 0x11107FbA1d2e1838dA980fE6D30e07089E11E4af
- **RPC**: https://testnet-rpc.roguechain.io
- **Region**: ord (Chicago - same as Blockster V2)

## Deployment

```bash
cd bundler
flyctl auth login
flyctl apps create rogue-bundler
flyctl secrets set BUILDER_PRIVATE_KEY=your_private_key_here -a rogue-bundler
flyctl deploy -a rogue-bundler
```

See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for detailed instructions.

## After Deployment

Update `assets/js/home_hooks.js` with your bundler URL:

```javascript
bundlerUrl: "https://rogue-bundler.fly.dev",
paymaster: async (userOp) => {
  return { paymasterAndData: paymasterAddress };
},
sponsorGas: true,
```

## Monitoring

```bash
# View logs
flyctl logs -a rogue-bundler --follow

# Check status
flyctl status -a rogue-bundler

# SSH into container
flyctl ssh console -a rogue-bundler
```

## Security

- Private key is stored as encrypted Fly.io secret
- Never commit private keys to git
- Keep bundler account funded with testnet ROGUE
- Monitor spending regularly

## Support

- Rundler: https://github.com/alchemyplatform/rundler
- Fly.io: https://fly.io/docs/

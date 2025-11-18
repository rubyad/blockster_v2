#!/usr/bin/env node

/**
 * Account Abstraction Deployment Verification Script
 *
 * Verifies all ERC-4337 components on both testnet and mainnet:
 * - EntryPoint contract
 * - ManagedAccountFactory
 * - Paymaster
 * - AccountExtension
 * - Stake amounts
 * - Deposit balances
 * - Bundler wallet balance
 */

const https = require('https');

// Network configurations
const NETWORKS = {
  testnet: {
    name: 'Rogue Testnet',
    chainId: 71499284269,
    rpc: 'https://testnet-rpc.roguechain.io',
    explorer: 'https://testnet-explorer.roguechain.io',
    contracts: {
      entryPoint: '0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789',
      factory: '0x39CeCF786830d1E073e737870E2A6e66fE92FDE9',
      paymaster: '0xd4ECb9C22e0c7495e167698cb8D0D9c84F65c02a',
      accountExtension: '0xdDd603b68BC40D16F4570A33198241991c56D304',
      bundlerWallet: '0xd75A64aDf49E180e6f4B1f1723ed4bdA16AFA06f'
    }
  },
  mainnet: {
    name: 'Rogue Mainnet',
    chainId: 560013,
    rpc: 'https://rpc.roguechain.io/rpc',
    explorer: 'https://roguescan.io',
    contracts: {
      entryPoint: '0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789',
      factory: '0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3',
      paymaster: '0x804cA06a85083eF01C9aE94bAE771446c25269a6',
      accountExtension: '0xB447e3dBcf25f5C9E2894b9d9f1207c8B13DdFfd',
      bundlerWallet: '0xd75A64aDf49E180e6f4B1f1723ed4bdA16AFA06f'
    }
  }
};

// Make JSON-RPC call
function rpcCall(rpc, method, params) {
  return new Promise((resolve, reject) => {
    const url = new URL(rpc);
    const postData = JSON.stringify({
      jsonrpc: '2.0',
      method: method,
      params: params,
      id: 1
    });

    const options = {
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.error) {
            reject(new Error(json.error.message || JSON.stringify(json.error)));
          } else {
            resolve(json.result);
          }
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

// Convert hex to decimal
function hexToDecimal(hex) {
  if (!hex || hex === '0x' || hex === '0x0') return 0n;
  return BigInt(hex);
}

// Format ROGUE amount
function formatROGUE(wei) {
  const amount = Number(wei) / 1e18;
  return amount.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// Check if contract is deployed
async function isContractDeployed(rpc, address) {
  const code = await rpcCall(rpc, 'eth_getCode', [address, 'latest']);
  return code && code !== '0x' && code.length > 2;
}

// Get balance
async function getBalance(rpc, address) {
  const balance = await rpcCall(rpc, 'eth_getBalance', [address, 'latest']);
  return hexToDecimal(balance);
}

// Get deposit info from EntryPoint
async function getDepositInfo(rpc, entryPoint, address) {
  // depositInfo(address) returns (uint112 deposit, bool staked, uint112 stake, uint32 unstakeDelaySec, uint48 withdrawTime)
  const data = '0x5287ce12' + address.slice(2).padStart(64, '0');
  const result = await rpcCall(rpc, 'eth_call', [{ to: entryPoint, data: data }, 'latest']);

  if (!result || result === '0x') {
    return { deposit: 0n, staked: false, stake: 0n, unstakeDelaySec: 0, withdrawTime: 0 };
  }

  // Parse the result
  const deposit = hexToDecimal('0x' + result.slice(2, 66));
  const staked = result.slice(66, 130) !== '0'.repeat(64);
  const stake = hexToDecimal('0x' + result.slice(130, 194));
  const unstakeDelaySec = hexToDecimal('0x' + result.slice(194, 258));
  const withdrawTime = hexToDecimal('0x' + result.slice(258, 322));

  return { deposit, staked, stake, unstakeDelaySec, withdrawTime };
}

// Verify a single network
async function verifyNetwork(network) {
  const results = {
    network: network.name,
    chainId: network.chainId,
    success: true,
    checks: []
  };

  console.log(`\n${'='.repeat(80)}`);
  console.log(`🔍 Verifying ${network.name} (Chain ID: ${network.chainId})`);
  console.log(`${'='.repeat(80)}\n`);

  try {
    // 1. Check EntryPoint
    console.log('1️⃣  Checking EntryPoint...');
    const entryPointDeployed = await isContractDeployed(network.rpc, network.contracts.entryPoint);
    results.checks.push({
      name: 'EntryPoint Deployed',
      address: network.contracts.entryPoint,
      status: entryPointDeployed ? '✅' : '❌',
      success: entryPointDeployed
    });
    console.log(`   ${entryPointDeployed ? '✅' : '❌'} EntryPoint: ${network.contracts.entryPoint}`);

    // 2. Check Factory
    console.log('\n2️⃣  Checking ManagedAccountFactory...');
    const factoryDeployed = await isContractDeployed(network.rpc, network.contracts.factory);
    results.checks.push({
      name: 'Factory Deployed',
      address: network.contracts.factory,
      status: factoryDeployed ? '✅' : '❌',
      success: factoryDeployed
    });
    console.log(`   ${factoryDeployed ? '✅' : '❌'} Factory: ${network.contracts.factory}`);

    // Check factory stake
    if (factoryDeployed) {
      const factoryInfo = await getDepositInfo(network.rpc, network.contracts.entryPoint, network.contracts.factory);
      const stakeOk = factoryInfo.staked && factoryInfo.stake >= 1n * 10n**18n;
      results.checks.push({
        name: 'Factory Staked',
        value: `${formatROGUE(factoryInfo.stake)} ROGUE`,
        status: stakeOk ? '✅' : '❌',
        success: stakeOk
      });
      console.log(`   ${stakeOk ? '✅' : '❌'} Factory Stake: ${formatROGUE(factoryInfo.stake)} ROGUE`);
      console.log(`   📊 Unstake Delay: ${factoryInfo.unstakeDelaySec} seconds`);
    }

    // 3. Check AccountExtension
    console.log('\n3️⃣  Checking AccountExtension...');
    const extensionDeployed = await isContractDeployed(network.rpc, network.contracts.accountExtension);
    results.checks.push({
      name: 'AccountExtension Deployed',
      address: network.contracts.accountExtension,
      status: extensionDeployed ? '✅' : '❌',
      success: extensionDeployed
    });
    console.log(`   ${extensionDeployed ? '✅' : '❌'} AccountExtension: ${network.contracts.accountExtension}`);

    // Check if extension is registered with factory
    if (factoryDeployed && extensionDeployed) {
      // getImplementationForFunction(bytes4 selector) - execute() selector is 0xb61d27f6
      const executeSelector = '0xce0b6013b61d27f600000000000000000000000000000000000000000000000000000000';
      const extensionAddr = await rpcCall(network.rpc, 'eth_call', [
        { to: network.contracts.factory, data: executeSelector },
        'latest'
      ]);
      const registered = extensionAddr && extensionAddr.toLowerCase().includes(network.contracts.accountExtension.slice(2).toLowerCase());
      results.checks.push({
        name: 'Extension Registered',
        status: registered ? '✅' : '❌',
        success: registered
      });
      console.log(`   ${registered ? '✅' : '❌'} Extension registered with factory`);
    }

    // 4. Check Paymaster
    console.log('\n4️⃣  Checking Paymaster...');
    const paymasterDeployed = await isContractDeployed(network.rpc, network.contracts.paymaster);
    results.checks.push({
      name: 'Paymaster Deployed',
      address: network.contracts.paymaster,
      status: paymasterDeployed ? '✅' : '❌',
      success: paymasterDeployed
    });
    console.log(`   ${paymasterDeployed ? '✅' : '❌'} Paymaster: ${network.contracts.paymaster}`);

    // Check paymaster stake and deposit
    if (paymasterDeployed) {
      const paymasterInfo = await getDepositInfo(network.rpc, network.contracts.entryPoint, network.contracts.paymaster);
      const stakeOk = paymasterInfo.staked && paymasterInfo.stake >= 1n * 10n**18n;
      const depositOk = paymasterInfo.deposit >= 100n * 10n**18n; // At least 100 ROGUE

      results.checks.push({
        name: 'Paymaster Staked',
        value: `${formatROGUE(paymasterInfo.stake)} ROGUE`,
        status: stakeOk ? '✅' : '❌',
        success: stakeOk
      });
      results.checks.push({
        name: 'Paymaster Deposit',
        value: `${formatROGUE(paymasterInfo.deposit)} ROGUE`,
        status: depositOk ? '✅' : '⚠️',
        success: depositOk
      });

      console.log(`   ${stakeOk ? '✅' : '❌'} Paymaster Stake: ${formatROGUE(paymasterInfo.stake)} ROGUE`);
      console.log(`   ${depositOk ? '✅' : '⚠️'} Paymaster Deposit: ${formatROGUE(paymasterInfo.deposit)} ROGUE`);
      console.log(`   📊 Unstake Delay: ${paymasterInfo.unstakeDelaySec} seconds`);
    }

    // 5. Check Bundler Wallet
    console.log('\n5️⃣  Checking Bundler Wallet...');
    const bundlerBalance = await getBalance(network.rpc, network.contracts.bundlerWallet);
    const bundlerOk = bundlerBalance >= 10n * 10n**18n; // At least 10 ROGUE
    results.checks.push({
      name: 'Bundler Balance',
      address: network.contracts.bundlerWallet,
      value: `${formatROGUE(bundlerBalance)} ROGUE`,
      status: bundlerOk ? '✅' : '⚠️',
      success: bundlerOk
    });
    console.log(`   ${bundlerOk ? '✅' : '⚠️'} Bundler Balance: ${formatROGUE(bundlerBalance)} ROGUE`);

    // Final verdict
    results.success = results.checks.every(check => check.success);

    console.log(`\n${'='.repeat(80)}`);
    if (results.success) {
      console.log(`✅ ${network.name} - ALL CHECKS PASSED`);
    } else {
      console.log(`❌ ${network.name} - SOME CHECKS FAILED`);
    }
    console.log(`${'='.repeat(80)}`);

  } catch (error) {
    console.error(`\n❌ Error verifying ${network.name}:`, error.message);
    results.success = false;
    results.error = error.message;
  }

  return results;
}

// Main function
async function main() {
  console.log('\n🚀 Account Abstraction Deployment Verification');
  console.log(`📅 ${new Date().toISOString()}\n`);

  const allResults = {};

  // Verify testnet
  allResults.testnet = await verifyNetwork(NETWORKS.testnet);

  // Verify mainnet
  allResults.mainnet = await verifyNetwork(NETWORKS.mainnet);

  // Summary
  console.log('\n\n' + '═'.repeat(80));
  console.log('📊 VERIFICATION SUMMARY');
  console.log('═'.repeat(80) + '\n');

  console.log(`Testnet: ${allResults.testnet.success ? '✅ PASSED' : '❌ FAILED'}`);
  console.log(`Mainnet: ${allResults.mainnet.success ? '✅ PASSED' : '❌ FAILED'}`);

  if (allResults.testnet.success && allResults.mainnet.success) {
    console.log('\n🎉 All networks are ready for Account Abstraction!');
    process.exit(0);
  } else {
    console.log('\n⚠️  Some networks have issues. Please review the output above.');
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}

module.exports = { verifyNetwork, NETWORKS };

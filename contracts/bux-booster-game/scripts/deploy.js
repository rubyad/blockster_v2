const { ethers } = require("hardhat");

// Helper function to retry failed transactions
async function retryWithBackoff(fn, maxRetries = 5, baseDelay = 2000) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === maxRetries - 1) throw error;
      const delay = baseDelay * Math.pow(2, i);
      console.log(`  Retry ${i + 1}/${maxRetries} after ${delay}ms...`);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}

// ERC20 ABI for mint and approve
const ERC20_ABI = [
  "function mint(address to, uint256 amount) external",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)"
];

// ERC1967 Proxy ABI (minimal)
const PROXY_ABI = [
  "constructor(address implementation, bytes data)"
];

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Settler Address: Regular EOA that calls submitCommitment() and settleBet()
  // Private key is stored in BUX Minter's environment file
  const settlerAddress = "0x4BBe1C90a0A6974d8d9A598d081309D8Ff27bb81";

  // Treasury Address: Same as deployer (owner) - receives house balance withdrawals
  // Update this if you want a different treasury address
  const treasuryAddress = deployer.address;

  console.log("\n=== Configuration ===");
  console.log("Settler:", settlerAddress);
  console.log("Treasury:", treasuryAddress);

  // Deploy implementation contract with explicit gas limit and retry logic
  console.log("\nDeploying BuxBoosterGame implementation...");
  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  const implementation = await retryWithBackoff(async () => {
    const impl = await BuxBoosterGame.deploy({ gasLimit: 10000000 });
    await impl.waitForDeployment();
    return impl;
  });
  const implementationAddress = await implementation.getAddress();
  console.log("Implementation deployed at:", implementationAddress);

  // Deploy ERC1967 Proxy
  console.log("\nDeploying ERC1967 Proxy...");

  // Encode initialize() call data
  const initData = BuxBoosterGame.interface.encodeFunctionData("initialize", [
    settlerAddress,
    treasuryAddress
  ]);

  // Deploy proxy using OpenZeppelin's ERC1967Proxy
  // We'll use a simple inline proxy deployment
  const ERC1967Proxy = await ethers.getContractFactory("ERC1967ProxySimple");
  let proxy;
  try {
    proxy = await ERC1967Proxy.deploy(implementationAddress, initData, { gasLimit: 500000 });
    await proxy.waitForDeployment();
  } catch (e) {
    // If ERC1967ProxySimple doesn't exist, deploy via raw bytecode
    console.log("Deploying proxy via raw transaction...");

    // Standard ERC1967Proxy bytecode from OpenZeppelin
    // This is the minimal proxy that delegates all calls to implementation
    const proxyBytecode = "0x608060405260405161045538038061045583398101604081905261002291610268565b61002c8282610033565b5050610352565b61003c826100a9565b6040516001600160a01b038316907fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b90600090a280511561009d5761009881836101039050565b505050565b6100a561017f565b5050565b806001600160a01b03163b6000036100e457604051634c9c8ce360e01b81526001600160a01b03821660048201526024015b60405180910390fd5b7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc80546001600160a01b0319166001600160a01b0392909216919091179055565b6060600080846001600160a01b03168460405161012091906102f9565b600060405180830381855af49150503d806000811461015b576040519150601f19603f3d011682016040523d82523d6000602084013e610160565b606091505b509092509050610171858383610186565b95945050505050565b565b6060826101a157610190826101db565b6101d4565b81511580156101b857506001600160a01b0384163b155b156101d157604051639996b31560e01b81526001600160a01b03851660048201526024016100db565b50805b9392505050565b8051156101eb5780518082602001fd5b604051630a12f52160e11b815260040160405180910390fd5b634e487b7160e01b600052604160045260246000fd5b60005b8381101561023557818101518382015260200161021d565b50506000910152565b600082601f83011261024f57600080fd5b81516001600160401b038082111561026957610269610204565b604051601f8301601f19908116603f0116810190828211818310171561029157610291610204565b816040528381528660208588010111156102aa57600080fd5b6102bb84602083016020890161021a565b9695505050505050565b80516001600160a01b03811681146102dc57600080fd5b919050565b634e487b7160e01b600052602160045260246000fd5b6000825161030b81846020870161021a565b9190910192915050565b6000806040838503121561032857600080fd5b610331836102c5565b60208401519092506001600160401b0381111561034d57600080fd5b6102bb8682870161023e565b60f58061036060003960006000f3fe6080604052600a600c565b005b60186014601a565b6051565b565b6000604c7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc546001600160a01b031690565b905090565b3660008037600080366000845af43d6000803e8080156070573d6000f35b3d6000fdfea26469706673582212205e2ff6c8e9fb72fbe0e8eab1d92c93b2c59f3b4e8a58a7f8f2f6f35b53d2c7d064736f6c63430008140033";

    // Actually, let's use the upgrades plugin but with forceImport to skip validation
    // and deploy via the factory pattern

    // Alternative: Direct deployment using ethers
    const proxyFactory = new ethers.ContractFactory(
      [
        "constructor(address _logic, bytes memory _data) payable"
      ],
      proxyBytecode,
      deployer
    );

    proxy = await proxyFactory.deploy(implementationAddress, initData, { gasLimit: 500000 });
    await proxy.waitForDeployment();
  }

  const proxyAddress = await proxy.getAddress();
  console.log("Proxy deployed at:", proxyAddress);

  // Connect to proxy as BuxBoosterGame
  const game = BuxBoosterGame.attach(proxyAddress);

  console.log("\n=== Deployment Successful ===");
  console.log("BuxBoosterGame Proxy:", proxyAddress);
  console.log("Implementation:", implementationAddress);

  // Verify initialization
  console.log("\nVerifying initialization...");
  const owner = await game.owner();
  const settler = await game.settler();
  const treasury = await game.treasury();
  console.log("Owner:", owner);
  console.log("Settler:", settler);
  console.log("Treasury:", treasury);

  // All 11 supported tokens
  const tokens = [
    { name: "BUX", address: "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8" },
    { name: "moonBUX", address: "0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5" },
    { name: "neoBUX", address: "0x423656448374003C2cfEaFF88D5F64fb3A76487C" },
    { name: "rogueBUX", address: "0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3" },
    { name: "flareBUX", address: "0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8" },
    { name: "nftBUX", address: "0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED" },
    { name: "nolchaBUX", address: "0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642" },
    { name: "solBUX", address: "0x92434779E281468611237d18AdE20A4f7F29DB38" },
    { name: "spaceBUX", address: "0xAcaCa77FbC674728088f41f6d978F0194cf3d55A" },
    { name: "tronBUX", address: "0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665" },
    { name: "tranBUX", address: "0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96" }
  ];

  // House balance: 1 million tokens (18 decimals)
  const houseBalance = ethers.parseEther("1000000"); // 1,000,000 tokens

  // Configure tokens, mint, and deposit house balance
  console.log("\nConfiguring tokens, minting 1M each, and depositing house balance...");

  for (const token of tokens) {
    console.log(`\n  Processing ${token.name}...`);

    // 1. Configure token as enabled
    const configTx = await game.configureToken(token.address, true, { gasLimit: 100000 });
    await configTx.wait();
    console.log(`    Configured as enabled`);

    // 2. Mint 1 million tokens to deployer
    const tokenContract = new ethers.Contract(token.address, ERC20_ABI, deployer);
    try {
      const mintTx = await tokenContract.mint(deployer.address, houseBalance, { gasLimit: 100000 });
      await mintTx.wait();
      console.log(`    Minted 1,000,000 tokens to deployer`);
    } catch (error) {
      console.log(`    Note: Could not mint (deployer may not be token owner): ${error.message}`);
      continue; // Skip deposit if mint failed
    }

    // 3. Approve game contract to spend tokens
    const approveTx = await tokenContract.approve(proxyAddress, houseBalance, { gasLimit: 100000 });
    await approveTx.wait();
    console.log(`    Approved game contract`);

    // 4. Deposit as house balance
    const depositTx = await game.depositHouseBalance(token.address, houseBalance, { gasLimit: 200000 });
    await depositTx.wait();
    console.log(`    Deposited 1,000,000 as house balance`);
  }

  console.log("\n=== Deployment Complete ===");
  console.log("Proxy Address (use this):", proxyAddress);
  console.log("Implementation Address:", implementationAddress);
  console.log("Owner:", deployer.address);
  console.log("Settler:", settlerAddress);
  console.log("Treasury:", treasuryAddress);
  console.log("\n=== Next Steps ===");
  console.log("1. Update CLAUDE.md with the proxy address");
  console.log("2. Update docs/bux_booster_onchain.md with the proxy address");
  console.log("3. Update BuxBoosterOnchain module @contract_address");
  console.log("4. Verify contract on Roguescan");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

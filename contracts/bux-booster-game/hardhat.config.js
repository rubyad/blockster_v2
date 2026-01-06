require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    rogueMainnet: {
      url: "https://rpc.roguechain.io/rpc",
      chainId: 560013,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
      gas: 5000000,
      gasPrice: 1000000000000,  // 1000 gwei - Rogue Chain base fee
      timeout: 120000,
      httpHeaders: {}
    },
    rogueMainnetAdmin: {
      url: "https://rpc.roguechain.io/rpc",
      chainId: 560013,
      accounts: process.env.ADMIN_PRIVATE_KEY ? [process.env.ADMIN_PRIVATE_KEY] : [],
      gas: 5000000,
      gasPrice: 1000000000000,  // 1000 gwei - Rogue Chain base fee
      timeout: 120000,
      httpHeaders: {}
    }
  }
};

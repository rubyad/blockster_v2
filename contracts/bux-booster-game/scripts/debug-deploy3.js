const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Debug deployment with account:", deployer.address);

  const BuxBoosterGame = await ethers.getContractFactory("BuxBoosterGame");
  const bytecode = BuxBoosterGame.bytecode;

  // Try with different gas values
  const gasValues = [
    {hex: "0x7A120", decimal: 500000},
    {hex: "0xF4240", decimal: 1000000},
    {hex: "0x1E8480", decimal: 2000000},
    {hex: "0x4C4B40", decimal: 5000000}
  ];

  for (const gas of gasValues) {
    console.log("\nTrying with gas:", gas.decimal);
    try {
      const result = await ethers.provider.send("eth_call", [{
        from: deployer.address,
        data: bytecode,
        gas: gas.hex
      }, "latest"]);
      console.log("Success! Result length:", result.length);
      break;
    } catch (error) {
      if (error.message.includes("500")) {
        console.log("RPC 500 error");
      } else {
        console.log("Error:", error.message.substring(0, 100));
      }
    }
  }
}

main().catch(console.error);

const { ethers } = require("hardhat");

async function main() {
  const BUX_BOOSTER_GAME = "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B";
  
  const abi = [
    'event BetPlaced(bytes32 indexed commitmentHash, address indexed player, address indexed token, uint256 amount, int8 difficulty)',
    'event BetSettled(bytes32 indexed commitmentHash, address indexed player, bool won, uint8[] results, uint256 payout, bytes32 serverSeed)',
    'function bets(bytes32) external view returns (address player, address token, uint256 amount, int8 difficulty, bytes32 commitmentHash, uint256 nonce, uint256 timestamp, uint8 status)'
  ];
  
  const [signer] = await ethers.getSigners();
  const contract = new ethers.Contract(BUX_BOOSTER_GAME, abi, signer);
  
  // Get BetPlaced events for ROGUE (token = 0x0)
  const filter = contract.filters.BetPlaced(null, null, "0x0000000000000000000000000000000000000000");
  const events = await contract.queryFilter(filter, -100000);
  
  console.log("Found " + events.length + " ROGUE BetPlaced events\n");
  
  for (const event of events) {
    const commitmentHash = event.args.commitmentHash;
    const amount = event.args.amount;
    const difficulty = event.args.difficulty;
    const betAmount = ethers.formatEther(amount);
    
    // Get bet status
    const bet = await contract.bets(commitmentHash);
    const statusNames = ['None', 'Placed', 'Settled'];
    const status = statusNames[bet.status] || bet.status;
    
    console.log("Commitment: " + commitmentHash.substring(0, 18) + "...");
    console.log("  Amount: " + betAmount + " ROGUE");
    console.log("  Difficulty: " + difficulty);
    console.log("  Status: " + status);
    console.log("  Nonce: " + bet.nonce.toString());
    console.log("");
  }
}

main().catch(console.error);

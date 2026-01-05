require('dotenv').config();

module.exports = {
  // Arbitrum One
  CHAIN_ID: 42161,
  CHAIN_NAME: 'Arbitrum One',
  RPC_URL: process.env.ARBITRUM_RPC_URL || 'https://snowy-little-cloud.arbitrum-mainnet.quiknode.pro/f4051c078b1e168f278c0780d1d12b817152c84d',

  // Contract
  CONTRACT_ADDRESS: '0x7176d2edd83aD037bd94b7eE717bd9F661F560DD',
  MINT_PRICE: '320000000000000000', // 0.32 ETH in wei
  MINT_PRICE_ETH: '0.32',

  // Supply limits
  CONTRACT_MAX_SUPPLY: 10000,  // Hardcoded in contract
  APP_MAX_SUPPLY: 2700,        // We stop minting at this number

  // Default affiliate (fallback)
  DEFAULT_AFFILIATE: '0xb91b270212F0F7504ECBa6Ff1d9c1f58DfcEEa14',

  // Affiliate linker wallet (authorized to call linkAffiliate on contract)
  AFFILIATE_LINKER_ADDRESS: '0x01436e73C4B4df2FEDA37f967C8eca1E510a7E73',
  AFFILIATE_LINKER_PRIVATE_KEY: process.env.AFFILIATE_LINKER_PRIVATE_KEY,

  // Affiliate percentages
  TIER1_PERCENTAGE: 20, // 20% = 0.064 ETH per mint
  TIER2_PERCENTAGE: 5,  // 5% = 0.016 ETH per mint

  // NFT Types with ImageKit URLs
  HOSTESSES: [
    {
      index: 0,
      name: 'Penelope Fatale',
      rarity: '0.5%',
      multiplier: 100,
      image: 'https://ik.imagekit.io/blockster/penelope.jpg',
      description: 'The rarest of them all - a true high roller\'s dream'
    },
    {
      index: 1,
      name: 'Mia Siren',
      rarity: '1%',
      multiplier: 90,
      image: 'https://ik.imagekit.io/blockster/mia.jpg',
      description: 'Her song lures the luckiest players'
    },
    {
      index: 2,
      name: 'Cleo Enchante',
      rarity: '3.5%',
      multiplier: 80,
      image: 'https://ik.imagekit.io/blockster/cleo.jpg',
      description: 'Egyptian royalty meets casino glamour'
    },
    {
      index: 3,
      name: 'Sophia Spark',
      rarity: '7.5%',
      multiplier: 70,
      image: 'https://ik.imagekit.io/blockster/sophia.jpg',
      description: 'Electrifying presence at every table'
    },
    {
      index: 4,
      name: 'Luna Mirage',
      rarity: '12.5%',
      multiplier: 60,
      image: 'https://ik.imagekit.io/blockster/luna.jpg',
      description: 'Mysterious as the moonlit casino floor'
    },
    {
      index: 5,
      name: 'Aurora Seductra',
      rarity: '25%',
      multiplier: 50,
      image: 'https://ik.imagekit.io/blockster/aurora.jpg',
      description: 'Lights up every room she enters'
    },
    {
      index: 6,
      name: 'Scarlett Ember',
      rarity: '25%',
      multiplier: 40,
      image: 'https://ik.imagekit.io/blockster/scarlett.jpg',
      description: 'Red hot luck follows her everywhere'
    },
    {
      index: 7,
      name: 'Vivienne Allure',
      rarity: '25%',
      multiplier: 30,
      image: 'https://ik.imagekit.io/blockster/vivienne.jpg',
      description: 'Classic elegance with a winning touch'
    }
  ],

  // Polling intervals
  POLL_INTERVAL_MS: 30000,        // 30 seconds for general sync
  MINT_POLL_INTERVAL_MS: 5000,    // 5 seconds for pending mints (fallback)
  OWNER_SYNC_INTERVAL_MS: 300000, // 5 minutes for full owner sync

  // Server
  PORT: process.env.PORT || 3001,

  // Database
  DB_PATH: process.env.DB_PATH || './data/highrollers.db',

  // Contract ABI (minimal required functions)
  CONTRACT_ABI: [
    // Read functions
    'function totalSupply() view returns (uint256)',
    'function getCurrentPrice() view returns (uint256)',
    'function getMaxSupply() view returns (uint256)',
    'function ownerOf(uint256 tokenId) view returns (address)',
    'function balanceOf(address owner) view returns (uint256)',
    'function s_tokenIdToHostess(uint256 tokenId) view returns (uint256)',
    'function getHostessByTokenId(uint256 tokenId) view returns (string)',
    'function getTokenIdsByWallet(address buyer) view returns (uint256[])',
    'function getBuyerInfo(address buyer) view returns (uint256 nftCount, uint256 spent, address affiliate, address affiliate2, uint256[] tokenIds)',
    'function getAffiliateInfo(address affiliate) view returns (uint256 buyerCount, uint256 referreeCount, uint256 referredAffiliatesCount, uint256 totalSpent, uint256 earnings, uint256 balance, address[] buyers, address[] referrees, address[] referredAffiliates, uint256[] tokenIds)',
    'function getAffiliate2Info(address affiliate) view returns (uint256 buyerCount2, uint256 referreeCount2, uint256 referredAffiliatesCount, uint256 totalSpent2, uint256 earnings2, uint256 balance, address[] buyers2, address[] referrees2, address[] referredAffiliates, uint256[] tokenIds2)',
    'function getTotalSalesVolume() view returns (uint256)',
    'function getTotalAffiliatesBalance() view returns (uint256)',
    'function s_requestIdToSender(uint256 requestId) view returns (address)',

    // Write functions
    'function requestNFT() payable returns (uint256 requestId)',
    'function linkAffiliate(address buyer, address affiliate) returns (address)',
    'function withdrawAffiliateBalance() external',

    // Events
    'event NFTRequested(uint256 requestId, address sender, uint256 currentPrice, uint256 tokenId)',
    'event NFTMinted(uint256 requestId, address recipient, uint256 currentPrice, uint256 tokenId, uint8 hostess, address affiliate, address affiliate2)',
    'event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)'
  ]
};

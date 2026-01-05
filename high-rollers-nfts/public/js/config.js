// High Rollers NFT - Frontend Configuration

const CONFIG = {
  // Arbitrum One
  CHAIN_ID: 42161,
  CHAIN_ID_HEX: '0xa4b1',
  CHAIN_NAME: 'Arbitrum One',
  RPC_URL: 'https://arb1.arbitrum.io/rpc',
  EXPLORER_URL: 'https://arbiscan.io',

  // Rogue Chain (for NFT Revenues)
  ROGUE_CHAIN_ID: 560013,
  ROGUE_EXPLORER_URL: 'https://roguescan.io',
  NFT_REWARDER_ADDRESS: '0x96aB9560f1407586faE2b69Dc7f38a59BEACC594',

  // Contract
  CONTRACT_ADDRESS: '0x7176d2edd83aD037bd94b7eE717bd9F661F560DD',
  MINT_PRICE: '320000000000000000', // 0.32 ETH in wei
  MINT_PRICE_ETH: '0.32',

  // Supply limits
  APP_MAX_SUPPLY: 2700,

  // Default affiliate
  DEFAULT_AFFILIATE: '0xb91b270212F0F7504ECBa6Ff1d9c1f58DfcEEa14',

  // API endpoints
  API_BASE: '/api',

  // WebSocket
  WS_URL: `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}`,

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

  // Contract ABI (minimal for frontend)
  CONTRACT_ABI: [
    'function requestNFT() payable returns (uint256 requestId)',
    'function linkAffiliate(address buyer, address affiliate) returns (address)',
    'function withdrawFromAffiliate() external returns (bool)',
    'function totalSupply() view returns (uint256)',
    'function ownerOf(uint256 tokenId) view returns (address)',
    'function s_tokenIdToHostess(uint256 tokenId) view returns (uint256)',
    'function getTokenIdsByWallet(address buyer) view returns (uint256[])',
    'function getAffiliateInfo(address affiliate) view returns (uint256 buyerCount, uint256 referreeCount, uint256 referredAffiliatesCount, uint256 totalSpent, uint256 earnings, uint256 balance, address[] buyers, address[] referrees, address[] referredAffiliates, uint256[] tokenIds)',
    'event NFTRequested(uint256 requestId, address sender, uint256 currentPrice, uint256 tokenId)',
    'event NFTMinted(uint256 requestId, address recipient, uint256 currentPrice, uint256 tokenId, uint8 hostess, address affiliate, address affiliate2)'
  ]
};

// Image optimization helper
const ImageKit = {
  transforms: {
    thumbnail: 'tr:w-100,h-100',
    card: 'tr:w-500,h-500',
    large: 'tr:w-800,h-800',
    banner: 'tr:w-1400,h-800'
  },

  getOptimizedUrl(baseUrl, size = 'card') {
    const transform = this.transforms[size] || this.transforms.card;
    return baseUrl.replace(
      'https://ik.imagekit.io/blockster/',
      `https://ik.imagekit.io/blockster/${transform}/`
    );
  },

  getHostessImage(hostessIndex, size = 'card') {
    const hostess = CONFIG.HOSTESSES[hostessIndex];
    if (!hostess) return '';
    return this.getOptimizedUrl(hostess.image, size);
  }
};

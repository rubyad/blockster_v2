const { ethers } = require('ethers');
const config = require('../config');

class ContractService {
  constructor() {
    this.provider = new ethers.JsonRpcProvider(config.RPC_URL);
    this.contract = new ethers.Contract(
      config.CONTRACT_ADDRESS,
      config.CONTRACT_ABI,
      this.provider
    );
  }

  // Read functions
  async getTotalSupply() {
    return await this.contract.totalSupply();
  }

  async getCurrentPrice() {
    return await this.contract.getCurrentPrice();
  }

  async getMaxSupply() {
    return await this.contract.getMaxSupply();
  }

  async getOwnerOf(tokenId) {
    try {
      return await this.contract.ownerOf(tokenId);
    } catch (error) {
      // Token doesn't exist
      return null;
    }
  }

  async getBalanceOf(owner) {
    return await this.contract.balanceOf(owner);
  }

  async getHostessIndex(tokenId) {
    return await this.contract.s_tokenIdToHostess(tokenId);
  }

  async getHostessName(tokenId) {
    return await this.contract.getHostessByTokenId(tokenId);
  }

  async getTokenIdsByWallet(wallet) {
    return await this.contract.getTokenIdsByWallet(wallet);
  }

  async getBuyerInfo(buyer) {
    const [nftCount, spent, affiliate, affiliate2, tokenIds] = await this.contract.getBuyerInfo(buyer);
    return {
      nftCount: Number(nftCount),
      spent: spent.toString(),
      affiliate,
      affiliate2,
      tokenIds: tokenIds.map(id => Number(id))
    };
  }

  async getAffiliateInfo(affiliate) {
    const [
      buyerCount,
      referreeCount,
      referredAffiliatesCount,
      totalSpent,
      earnings,
      balance,
      buyers,
      referrees,
      referredAffiliates,
      tokenIds
    ] = await this.contract.getAffiliateInfo(affiliate);

    return {
      buyerCount: Number(buyerCount),
      referreeCount: Number(referreeCount),
      referredAffiliatesCount: Number(referredAffiliatesCount),
      totalSpent: totalSpent.toString(),
      earnings: earnings.toString(),
      balance: balance.toString(),
      buyers,
      referrees,
      referredAffiliates,
      tokenIds: tokenIds.map(id => Number(id))
    };
  }

  async getAffiliate2Info(affiliate) {
    const [
      buyerCount2,
      referreeCount2,
      referredAffiliatesCount,
      totalSpent2,
      earnings2,
      balance,
      buyers2,
      referrees2,
      referredAffiliates,
      tokenIds2
    ] = await this.contract.getAffiliate2Info(affiliate);

    return {
      buyerCount: Number(buyerCount2),
      referreeCount: Number(referreeCount2),
      referredAffiliatesCount: Number(referredAffiliatesCount),
      totalSpent: totalSpent2.toString(),
      earnings: earnings2.toString(),
      balance: balance.toString(),
      buyers: buyers2,
      referrees: referrees2,
      referredAffiliates,
      tokenIds: tokenIds2.map(id => Number(id))
    };
  }

  async getTotalSalesVolume() {
    return await this.contract.getTotalSalesVolume();
  }

  async getTotalAffiliatesBalance() {
    return await this.contract.getTotalAffiliatesBalance();
  }

  async getRequestSender(requestId) {
    return await this.contract.s_requestIdToSender(requestId);
  }

  // Batch operations
  async getNFTDetails(tokenId) {
    try {
      const [owner, hostessIndex] = await Promise.all([
        this.getOwnerOf(tokenId),
        this.getHostessIndex(tokenId)
      ]);

      if (!owner) return null;

      const hostess = config.HOSTESSES[Number(hostessIndex)];
      return {
        tokenId,
        owner,
        hostessIndex: Number(hostessIndex),
        hostessName: hostess?.name || 'Unknown',
        hostessRarity: hostess?.rarity || 'Unknown',
        hostessMultiplier: hostess?.multiplier || 0,
        hostessImage: hostess?.image || ''
      };
    } catch (error) {
      return null;
    }
  }

  async getNFTDetailsBatch(tokenIds) {
    const results = await Promise.all(
      tokenIds.map(tokenId => this.getNFTDetails(tokenId))
    );
    return results.filter(r => r !== null);
  }

  // Get collection stats
  async getCollectionStats() {
    const [totalSupply, currentPrice, totalVolume, affiliatesBalance] = await Promise.all([
      this.getTotalSupply(),
      this.getCurrentPrice(),
      this.getTotalSalesVolume(),
      this.getTotalAffiliatesBalance()
    ]);

    const minted = Number(totalSupply);
    const remaining = config.APP_MAX_SUPPLY - minted;

    return {
      totalSupply: totalSupply.toString(),
      totalMinted: minted,
      maxSupply: config.APP_MAX_SUPPLY,
      remaining: Math.max(0, remaining),
      currentPrice: currentPrice.toString(),
      currentPriceETH: ethers.formatEther(currentPrice),
      totalVolume: totalVolume.toString(),
      totalVolumeETH: ethers.formatEther(totalVolume),
      affiliatesBalance: affiliatesBalance.toString(),
      affiliatesBalanceETH: ethers.formatEther(affiliatesBalance),
      soldOut: minted >= config.APP_MAX_SUPPLY
    };
  }

  // Query past events
  async queryNFTMintedEvents(fromBlock, toBlock = 'latest') {
    const filter = this.contract.filters.NFTMinted();
    return await this.contract.queryFilter(filter, fromBlock, toBlock);
  }

  async queryTransferEvents(fromBlock, toBlock = 'latest') {
    const filter = this.contract.filters.Transfer();
    return await this.contract.queryFilter(filter, fromBlock, toBlock);
  }

  async queryNFTRequestedEvents(fromBlock, toBlock = 'latest') {
    const filter = this.contract.filters.NFTRequested();
    return await this.contract.queryFilter(filter, fromBlock, toBlock);
  }

  // Get current block number
  async getBlockNumber() {
    return await this.provider.getBlockNumber();
  }

  // Get raw provider for advanced operations
  getProvider() {
    return this.provider;
  }

  // Get raw contract for event listening
  getContract() {
    return this.contract;
  }
}

module.exports = ContractService;

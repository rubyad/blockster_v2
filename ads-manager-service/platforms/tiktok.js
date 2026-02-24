/**
 * TikTok Marketing API wrapper.
 * Placeholder for Phase 4 — requires app review with demo video.
 *
 * Required env vars:
 *   TIKTOK_ACCESS_TOKEN, TIKTOK_ADVERTISER_ID
 */

async function createCampaign(_params) {
  throw new Error("TikTok integration not yet implemented (Phase 4)");
}

async function getCampaign(_campaignId) {
  throw new Error("TikTok integration not yet implemented (Phase 4)");
}

async function pauseCampaign(_campaignId) {
  throw new Error("TikTok integration not yet implemented (Phase 4)");
}

async function resumeCampaign(_campaignId) {
  throw new Error("TikTok integration not yet implemented (Phase 4)");
}

async function getCampaignAnalytics(_campaignId, _dateRange) {
  throw new Error("TikTok integration not yet implemented (Phase 4)");
}

module.exports = {
  createCampaign,
  getCampaign,
  pauseCampaign,
  resumeCampaign,
  getCampaignAnalytics,
};

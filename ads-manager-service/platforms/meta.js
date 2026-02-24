/**
 * Meta (Facebook/Instagram) Marketing API wrapper.
 * Placeholder for Phase 2 — requires App Review + Business Verification.
 *
 * Required env vars:
 *   META_ACCESS_TOKEN, META_AD_ACCOUNT_ID
 */

async function createCampaign(_params) {
  throw new Error("Meta integration not yet implemented (Phase 2)");
}

async function getCampaign(_campaignId) {
  throw new Error("Meta integration not yet implemented (Phase 2)");
}

async function pauseCampaign(_campaignId) {
  throw new Error("Meta integration not yet implemented (Phase 2)");
}

async function resumeCampaign(_campaignId) {
  throw new Error("Meta integration not yet implemented (Phase 2)");
}

async function getCampaignAnalytics(_campaignId, _dateRange) {
  throw new Error("Meta integration not yet implemented (Phase 2)");
}

module.exports = {
  createCampaign,
  getCampaign,
  pauseCampaign,
  resumeCampaign,
  getCampaignAnalytics,
};

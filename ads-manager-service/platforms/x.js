/**
 * X (Twitter) Ads API wrapper.
 * Uses OAuth 1.0a for authentication (no official SDK).
 * Hierarchy: Campaign -> Line Item -> Promoted Tweet
 *
 * Required env vars:
 *   X_ADS_CONSUMER_KEY, X_ADS_CONSUMER_SECRET
 *   X_ADS_ACCESS_TOKEN, X_ADS_ACCESS_TOKEN_SECRET
 *   X_ADS_ACCOUNT_ID
 */

const crypto = require("crypto");
const OAuth = require("oauth-1.0a");
const CryptoJS = require("crypto-js");

const BASE_URL = "https://ads-api.x.com/12";

function getOAuth() {
  return OAuth({
    consumer: {
      key: process.env.X_ADS_CONSUMER_KEY,
      secret: process.env.X_ADS_CONSUMER_SECRET,
    },
    signature_method: "HMAC-SHA1",
    hash_function(baseString, key) {
      return CryptoJS.HmacSHA1(baseString, key).toString(CryptoJS.enc.Base64);
    },
  });
}

function getToken() {
  return {
    key: process.env.X_ADS_ACCESS_TOKEN,
    secret: process.env.X_ADS_ACCESS_TOKEN_SECRET,
  };
}

async function xRequest(method, path, body = null) {
  const url = `${BASE_URL}${path}`;
  const oauth = getOAuth();
  const requestData = { url, method };
  const authHeader = oauth.toHeader(oauth.authorize(requestData, getToken()));

  const options = {
    method,
    headers: {
      ...authHeader,
      "Content-Type": "application/json",
    },
  };

  if (body) {
    options.body = JSON.stringify(body);
  }

  const response = await fetch(url, options);
  const data = await response.json();

  if (!response.ok) {
    const errMsg = data?.errors?.[0]?.message || JSON.stringify(data);
    throw new Error(`X API error (${response.status}): ${errMsg}`);
  }

  return data;
}

function accountId() {
  return process.env.X_ADS_ACCOUNT_ID;
}

/**
 * Create a campaign on X.
 */
async function createCampaign({ name, objective, dailyBudget, startTime, endTime }) {
  // Map our objectives to X's funding instruments + objectives
  const objectiveMap = {
    traffic: "WEBSITE_CLICKS",
    signups: "WEBSITE_CONVERSIONS",
    engagement: "ENGAGEMENTS",
    purchases: "WEBSITE_CONVERSIONS",
  };

  // Get funding instrument
  const fundingRes = await xRequest("GET", `/accounts/${accountId()}/funding_instruments`);
  const fundingId = fundingRes.data?.[0]?.id;

  if (!fundingId) throw new Error("No funding instrument found for X account");

  const params = {
    name,
    funding_instrument_id: fundingId,
    daily_budget_amount_local_micro: Math.round(dailyBudget * 1_000_000),
    entity_status: "PAUSED", // Always create paused, Elixir activates after review
    objective: objectiveMap[objective] || "WEBSITE_CLICKS",
  };

  if (startTime) params.start_time = startTime;
  if (endTime) params.end_time = endTime;

  const result = await xRequest("POST", `/accounts/${accountId()}/campaigns`, params);
  return {
    campaign_id: result.data?.id,
    platform: "x",
    status: "paused",
    raw: result.data,
  };
}

/**
 * Get campaign status and basic metrics.
 */
async function getCampaign(campaignId) {
  const result = await xRequest("GET", `/accounts/${accountId()}/campaigns/${campaignId}`);
  return result.data;
}

/**
 * Pause a campaign.
 */
async function pauseCampaign(campaignId) {
  return xRequest("PUT", `/accounts/${accountId()}/campaigns/${campaignId}`, {
    entity_status: "PAUSED",
  });
}

/**
 * Resume (unpause) a campaign.
 */
async function resumeCampaign(campaignId) {
  return xRequest("PUT", `/accounts/${accountId()}/campaigns/${campaignId}`, {
    entity_status: "ACTIVE",
  });
}

/**
 * Get campaign analytics for a date range.
 */
async function getCampaignAnalytics(campaignId, { startDate, endDate }) {
  const params = new URLSearchParams({
    entity: "CAMPAIGN",
    entity_ids: campaignId,
    start_time: startDate,
    end_time: endDate,
    granularity: "DAY",
    metric_groups: "ENGAGEMENT,BILLING,VIDEO",
    placement: "ALL_ON_TWITTER",
  });

  const result = await xRequest(
    "GET",
    `/stats/accounts/${accountId()}?${params.toString()}`
  );

  return result.data;
}

module.exports = {
  createCampaign,
  getCampaign,
  pauseCampaign,
  resumeCampaign,
  getCampaignAnalytics,
};

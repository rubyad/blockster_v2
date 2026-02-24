/**
 * Telegram Bot API wrapper for organic channel posting.
 * Telegram Ads API does not exist — paid ads are managed via ads.telegram.org dashboard.
 * This module handles bot-powered organic channel posts only.
 *
 * Required env vars:
 *   TELEGRAM_BOT_TOKEN, TELEGRAM_CHANNEL_ID
 */

const BASE_URL = "https://api.telegram.org";

async function botRequest(method, params = {}) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new Error("TELEGRAM_BOT_TOKEN not configured");

  const url = `${BASE_URL}/bot${token}/${method}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(params),
  });

  const data = await response.json();
  if (!data.ok) {
    throw new Error(`Telegram API error: ${data.description}`);
  }
  return data.result;
}

/**
 * Post a message to the Blockster Telegram channel.
 * This is organic posting, not paid ads.
 */
async function postToChannel({ text, imageUrl, parseMode = "HTML" }) {
  const chatId = process.env.TELEGRAM_CHANNEL_ID;
  if (!chatId) throw new Error("TELEGRAM_CHANNEL_ID not configured");

  if (imageUrl) {
    return botRequest("sendPhoto", {
      chat_id: chatId,
      photo: imageUrl,
      caption: text,
      parse_mode: parseMode,
    });
  }

  return botRequest("sendMessage", {
    chat_id: chatId,
    text,
    parse_mode: parseMode,
  });
}

// Campaign stubs — Telegram paid ads have no API
async function createCampaign(_params) {
  throw new Error("Telegram paid ads have no API. Use organic channel posting or manage ads at ads.telegram.org");
}

async function getCampaign(_campaignId) {
  throw new Error("Telegram paid ads have no API");
}

async function pauseCampaign(_campaignId) {
  throw new Error("Telegram paid ads have no API");
}

async function resumeCampaign(_campaignId) {
  throw new Error("Telegram paid ads have no API");
}

async function getCampaignAnalytics(_campaignId, _dateRange) {
  throw new Error("Telegram paid ads have no API");
}

module.exports = {
  postToChannel,
  createCampaign,
  getCampaign,
  pauseCampaign,
  resumeCampaign,
  getCampaignAnalytics,
};

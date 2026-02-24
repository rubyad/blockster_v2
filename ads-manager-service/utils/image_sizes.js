/**
 * Platform-specific image dimensions for ad creatives.
 * Used by the image generation and brand overlay modules (Phase 2).
 */

module.exports = {
  x: {
    feed: { width: 1200, height: 675, label: "X Feed Image" },
    card: { width: 800, height: 418, label: "X Website Card" },
  },
  meta: {
    feed: { width: 1080, height: 1080, label: "Meta Feed Square" },
    stories: { width: 1080, height: 1920, label: "Meta Stories/Reels" },
    landscape: { width: 1200, height: 628, label: "Meta Landscape" },
  },
  tiktok: {
    vertical: { width: 1080, height: 1920, label: "TikTok Vertical" },
    square: { width: 1080, height: 1080, label: "TikTok Square" },
  },
  telegram: {
    // Telegram sponsored messages are text-only
    // Channel posts can include images
    channel: { width: 800, height: 600, label: "Telegram Channel" },
  },
};

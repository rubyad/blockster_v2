const express = require("express");
const router = express.Router();

function getPlatformModule(platform) {
  const modules = {
    x: require("../platforms/x"),
    meta: require("../platforms/meta"),
    tiktok: require("../platforms/tiktok"),
    telegram: require("../platforms/telegram"),
  };
  const mod = modules[platform];
  if (!mod) throw Object.assign(new Error(`Unknown platform: ${platform}`), { status: 400 });
  return mod;
}

// GET /analytics/campaign/:id — Get campaign analytics
router.get("/campaign/:id", async (req, res, next) => {
  try {
    const { platform, start_date, end_date } = req.query;
    if (!platform) return res.status(400).json({ error: "platform query param required" });

    const platformModule = getPlatformModule(platform);
    const data = await platformModule.getCampaignAnalytics(req.params.id, {
      startDate: start_date,
      endDate: end_date,
    });

    res.json(data);
  } catch (err) {
    next(err);
  }
});

// GET /analytics/:platform — Get platform-level analytics
router.get("/:platform", async (req, res, next) => {
  try {
    // Phase 1: Return stub data
    res.json({
      platform: req.params.platform,
      total_spend: 0,
      total_impressions: 0,
      total_clicks: 0,
      total_conversions: 0,
      active_campaigns: 0,
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

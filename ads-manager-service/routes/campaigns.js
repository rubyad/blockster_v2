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

// POST /campaigns — Create campaign on platform
router.post("/", async (req, res, next) => {
  try {
    const { platform, name, objective, daily_budget, lifetime_budget, targeting, account_id } = req.body;

    if (!platform || !name) {
      return res.status(400).json({ error: "platform and name are required" });
    }

    const platformModule = getPlatformModule(platform);
    const result = await platformModule.createCampaign({
      name,
      objective: objective || "traffic",
      dailyBudget: daily_budget || 10,
      lifetimeBudget: lifetime_budget,
      targeting,
      accountId: account_id,
    });

    res.json(result);
  } catch (err) {
    next(err);
  }
});

// GET /campaigns/:id — Get campaign status
router.get("/:id", async (req, res, next) => {
  try {
    const { platform } = req.query;
    if (!platform) return res.status(400).json({ error: "platform query param required" });

    const platformModule = getPlatformModule(platform);
    const result = await platformModule.getCampaign(req.params.id);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

// POST /campaigns/:id/pause — Pause campaign
router.post("/:id/pause", async (req, res, next) => {
  try {
    const { platform } = req.body;
    if (!platform) return res.status(400).json({ error: "platform is required" });

    const platformModule = getPlatformModule(platform);
    await platformModule.pauseCampaign(req.params.id);
    res.json({ status: "paused", campaign_id: req.params.id });
  } catch (err) {
    next(err);
  }
});

// POST /campaigns/:id/resume — Resume campaign
router.post("/:id/resume", async (req, res, next) => {
  try {
    const { platform } = req.body;
    if (!platform) return res.status(400).json({ error: "platform is required" });

    const platformModule = getPlatformModule(platform);
    await platformModule.resumeCampaign(req.params.id);
    res.json({ status: "active", campaign_id: req.params.id });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

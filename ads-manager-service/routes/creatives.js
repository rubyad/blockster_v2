const express = require("express");
const router = express.Router();

// POST /creatives — Upload creative to platform
// Phase 2: Will integrate with platform-specific creative upload APIs
router.post("/", async (req, res, next) => {
  try {
    const { platform, campaign_id, type, headline, body, cta_text, image_url, video_url } = req.body;

    if (!platform || !campaign_id) {
      return res.status(400).json({ error: "platform and campaign_id are required" });
    }

    // Phase 1: Return a stub response — actual platform upload happens in later phases
    res.json({
      creative_id: `stub_${Date.now()}`,
      platform,
      campaign_id,
      type: type || "image",
      status: "draft",
    });
  } catch (err) {
    next(err);
  }
});

// GET /creatives/:id/performance — Get creative-level metrics
router.get("/:id/performance", async (req, res, next) => {
  try {
    const { platform } = req.query;
    if (!platform) return res.status(400).json({ error: "platform query param required" });

    // Phase 1: Return stub metrics
    res.json({
      creative_id: req.params.id,
      impressions: 0,
      clicks: 0,
      conversions: 0,
      spend: 0,
      ctr: 0,
      cpc: 0,
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;

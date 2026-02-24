const express = require("express");
const router = express.Router();
const copywriter = require("../creative/copywriter");

// POST /generate/copy — Generate ad copy variants using Claude API
router.post("/copy", async (req, res, next) => {
  try {
    const { content_type, title, excerpt, platform, objective, num_variants } = req.body;

    if (!title || !platform) {
      return res.status(400).json({ error: "title and platform are required" });
    }

    const variants = await copywriter.generateCopy({
      contentType: content_type || "post",
      title,
      excerpt: excerpt || "",
      platform,
      objective: objective || "traffic",
      numVariants: num_variants || 3,
    });

    res.json({ variants });
  } catch (err) {
    next(err);
  }
});

// POST /generate/image — Generate ad images (Phase 2)
router.post("/image", async (_req, res) => {
  res.status(501).json({ error: "Image generation not yet implemented (Phase 2)" });
});

// POST /generate/video — Generate ad video (Phase 4)
router.post("/video", async (_req, res) => {
  res.status(501).json({ error: "Video generation not yet implemented (Phase 4)" });
});

// POST /generate/overlay — Apply brand overlay to image (Phase 2)
router.post("/overlay", async (_req, res) => {
  res.status(501).json({ error: "Brand overlay not yet implemented (Phase 2)" });
});

module.exports = router;

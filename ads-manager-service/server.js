const express = require("express");
const auth = require("./middleware/auth");

const campaignRoutes = require("./routes/campaigns");
const creativeRoutes = require("./routes/creatives");
const generateRoutes = require("./routes/generate");
const analyticsRoutes = require("./routes/analytics");

const app = express();
app.use(express.json({ limit: "10mb" }));

// Health check (no auth)
app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "ads-manager", version: "1.0.0" });
});

// All routes require auth
app.use(auth);

app.use("/campaigns", campaignRoutes);
app.use("/creatives", creativeRoutes);
app.use("/generate", generateRoutes);
app.use("/analytics", analyticsRoutes);

// Error handler
app.use((err, _req, res, _next) => {
  console.error("[ERROR]", err.message, err.stack);
  res.status(err.status || 500).json({ error: err.message || "Internal server error" });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`[ads-manager] listening on port ${PORT}`);
});

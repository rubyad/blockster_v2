/**
 * Bearer token authentication middleware.
 * The Elixir backend sends: Authorization: Bearer <ADS_SERVICE_SECRET>
 */
module.exports = function auth(req, res, next) {
  const header = req.headers.authorization;

  if (!header || !header.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Missing or invalid Authorization header" });
  }

  const token = header.slice(7);
  const secret = process.env.ADS_SERVICE_SECRET;

  if (!secret) {
    console.error("[auth] ADS_SERVICE_SECRET not configured");
    return res.status(500).json({ error: "Service misconfigured" });
  }

  if (token !== secret) {
    return res.status(403).json({ error: "Invalid token" });
  }

  next();
};

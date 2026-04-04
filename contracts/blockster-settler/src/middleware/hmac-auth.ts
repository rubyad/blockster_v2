import { Request, Response, NextFunction } from "express";
import { createHmac, timingSafeEqual } from "crypto";
import { API_SECRET } from "../config";

/**
 * HMAC authentication middleware.
 *
 * Expects headers:
 * - x-signature: HMAC-SHA256 of request body using API_SECRET
 * - x-timestamp: Unix timestamp (must be within 5 minutes)
 *
 * In dev mode (SETTLER_API_SECRET=dev-secret), all requests are allowed.
 */
export function hmacAuth(req: Request, res: Response, next: NextFunction) {
  // Skip auth in dev mode
  if (API_SECRET === "dev-secret") {
    return next();
  }

  const signature = req.headers["x-signature"] as string;
  const timestamp = req.headers["x-timestamp"] as string;

  if (!signature || !timestamp) {
    return res.status(401).json({ error: "Missing authentication headers" });
  }

  // Check timestamp freshness (5 minute window)
  const now = Math.floor(Date.now() / 1000);
  const ts = parseInt(timestamp, 10);
  if (isNaN(ts) || Math.abs(now - ts) > 300) {
    return res.status(401).json({ error: "Timestamp expired" });
  }

  // Compute expected signature
  const body = typeof req.body === "string" ? req.body : JSON.stringify(req.body);
  const payload = `${timestamp}.${body}`;
  const expected = createHmac("sha256", API_SECRET)
    .update(payload)
    .digest("hex");

  // Timing-safe comparison
  try {
    const sigBuf = Buffer.from(signature, "hex");
    const expectedBuf = Buffer.from(expected, "hex");
    if (sigBuf.length !== expectedBuf.length || !timingSafeEqual(sigBuf, expectedBuf)) {
      return res.status(401).json({ error: "Invalid signature" });
    }
  } catch {
    return res.status(401).json({ error: "Invalid signature format" });
  }

  next();
}

/**
 * Ad copy generation using Claude API.
 * Generates platform-specific ad copy variants for A/B testing.
 */

const Anthropic = require("@anthropic-ai/sdk");

function getClient() {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not configured");
  return new Anthropic({ apiKey });
}

const PLATFORM_SPECS = {
  x: {
    name: "X (Twitter)",
    headlineMax: 50,
    bodyMax: 250,
    ctaOptions: ["Learn More", "Read Now", "Sign Up", "Play Now", "Shop Now"],
    notes: "Keep punchy. Use emoji sparingly. Hashtags count toward character limit.",
  },
  meta: {
    name: "Meta (Facebook/Instagram)",
    headlineMax: 40,
    bodyMax: 125,
    ctaOptions: ["Learn More", "Sign Up", "Shop Now", "Play Game", "Get Offer"],
    notes: "Primary text appears above the image. Headline appears below. Avoid clickbait.",
  },
  tiktok: {
    name: "TikTok",
    headlineMax: 20,
    bodyMax: 100,
    ctaOptions: ["Learn More", "Sign Up", "Shop Now", "Play Now"],
    notes: "Ultra-short, Gen Z tone. No corporate language. Emoji-friendly.",
  },
  telegram: {
    name: "Telegram",
    headlineMax: 40,
    bodyMax: 160,
    ctaOptions: ["Read Article", "Join Channel", "Try It Free", "Get BUX"],
    notes: "Sponsored messages in channels. Direct, informative tone. No images in ads.",
  },
};

/**
 * Generate ad copy variants for a given platform.
 */
async function generateCopy({ contentType, title, excerpt, platform, objective, numVariants = 3 }) {
  const client = getClient();
  const spec = PLATFORM_SPECS[platform] || PLATFORM_SPECS.x;

  const prompt = `Generate ${numVariants} ad copy variants for a ${spec.name} ad campaign.

Content to promote:
- Type: ${contentType}
- Title: "${title}"
- Description: "${excerpt}"

Campaign objective: ${objective}

Platform requirements:
- Headline: max ${spec.headlineMax} characters
- Body text: max ${spec.bodyMax} characters
- CTA options: ${spec.ctaOptions.join(", ")}
- ${spec.notes}

Brand: Blockster — a web3 content platform where users earn BUX tokens for reading articles, playing games, and shopping.

Return EXACTLY ${numVariants} variants as a JSON array. Each variant must have:
- "headline": string (under ${spec.headlineMax} chars)
- "body": string (under ${spec.bodyMax} chars)
- "cta_text": string (from the CTA options above)
- "hashtags": array of strings (2-4 relevant hashtags, without # prefix)

Make each variant distinctly different in tone/angle:
- Variant 1: Informational/educational
- Variant 2: Curiosity/intrigue
- Variant 3: Value proposition/benefit
${numVariants > 3 ? "- Additional variants: Mix of urgency, social proof, or humor" : ""}

Return ONLY the JSON array, no other text.`;

  const response = await client.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 1024,
    messages: [{ role: "user", content: prompt }],
  });

  const text = response.content[0]?.text || "[]";

  try {
    // Extract JSON from response (handle markdown code blocks)
    const jsonMatch = text.match(/\[[\s\S]*\]/);
    if (!jsonMatch) throw new Error("No JSON array found in response");
    return JSON.parse(jsonMatch[0]);
  } catch (parseErr) {
    console.error("[copywriter] Failed to parse Claude response:", text);
    throw new Error(`Failed to parse copy generation response: ${parseErr.message}`);
  }
}

module.exports = { generateCopy };

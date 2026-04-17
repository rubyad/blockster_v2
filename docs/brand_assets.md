# Brand Assets

Canonical ImageKit URLs for Blockster logo and icon files. Origin bucket: `s3://blockster-images/brand/`.

All files are PNG. Any size can be served via ImageKit transforms, e.g. `?tr=w-512,h-512`.

**Public-facing media kit page**: [`/media-kit`](https://blockster.com/media-kit) — rendered by `lib/blockster_v2_web/live/media_kit_live.ex`.

## Download everything

| Bundle | URL |
|---|---|
| All PNGs (zip, 970 KB) | `https://ik.imagekit.io/blockster/brand/blockster-brand-assets.zip` |

## Wordmark — light surfaces (black text)

| Variant | URL |
|---|---|
| White bg · 1000×750 | `https://ik.imagekit.io/blockster/brand/blockster-wordmark-light-1000x750.png` |
| White bg · 3000×2250 | `https://ik.imagekit.io/blockster/brand/blockster-wordmark-light-3000x2250.png` |
| Transparent · 1000×750 | `https://ik.imagekit.io/blockster/brand/blockster-wordmark-light-transparent-1000x750.png` |
| Transparent · 3000×2250 | `https://ik.imagekit.io/blockster/brand/blockster-wordmark-light-transparent-3000x2250.png` |

## Wordmark — dark surfaces (light text #E8E4DD)

| Variant | URL |
|---|---|
| Black bg · 1000×750 | `https://ik.imagekit.io/blockster/brand/blockster-wordmark-dark-1000x750.png` |
| Black bg · 3000×2250 | `https://ik.imagekit.io/blockster/brand/blockster-wordmark-dark-3000x2250.png` |
| Transparent · 1000×750 | `https://ik.imagekit.io/blockster/brand/blockster-wordmark-dark-transparent-1000x750.png` |
| Transparent · 3000×2250 | `https://ik.imagekit.io/blockster/brand/blockster-wordmark-dark-transparent-3000x2250.png` |

## Icon (lime circle with lightning bolt, transparent PNG)

| Variant | URL |
|---|---|
| Small · 256×256 | `https://ik.imagekit.io/blockster/brand/blockster-icon-256.png` |
| Large · 2048×2048 | `https://ik.imagekit.io/blockster/brand/blockster-icon-2048.png` |
| Legacy root (used by `lightning_icon/1`) | `https://ik.imagekit.io/blockster/blockster-icon.png` |

## Re-generating

Source HTML and render/upload scripts live at:
- `/tmp/render_and_upload.sh` — Chrome headless renderer (3× supersampled → 1000×750)
- `/tmp/upload_s3.py` — boto3 upload to `blockster-images/brand/`

Local copies of all files also saved to `priv/static/images/` for the 1000×750 and 3000×2250 wordmark.

## Colors

- Lime accent: `#CAFC00`
- Dark text / surface: `#0a0a0a` (near-black), `#141414` (body text)
- Light type on dark: `#E8E4DD`
- Light surface: `#fafaf9`

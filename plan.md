# BlocksterV2 Blog Platform Plan

## Project Overview
Building a crypto/blockchain themed blog platform with rich text editing (Quill.js) and S3 image uploads, matching the exact design from https://blockerstaging2.netlify.app/unregistered-users

## Detailed Implementation Steps

- [x] Generate Phoenix LiveView project with PostgreSQL
- [x] Create detailed plan.md
- [ ] Start server and create static mockup (1 step)
  - Replace home.html.heex with full static mockup matching the Blockster design
  - Vibrant crypto-themed design with gradients, bold colors, card layouts
- [ ] Add AWS S3 dependencies and configuration (1 step)
  - Add `{:ex_aws, "~> 2.5"}`, `{:ex_aws_s3, "~> 2.5"}`, `{:hackney, "~> 1.20"}`, `{:sweet_xml, "~> 0.7"}`
  - Configure S3 bucket settings in config/dev.exs and config/runtime.exs
  - Set up .env instructions for AWS credentials
- [ ] Create Blog schemas and migrations (2 steps)
  - Create Post schema with fields: title, slug, content (rich text JSON), excerpt, author_name, published_at, view_count, category
  - Create migration and run it
  - Create Blog context with CRUD operations
- [ ] Set up Quill.js integration (2 steps)
  - Add Quill.js CDN links to root.html.heex
  - Create custom JS hook for Quill editor with S3 image upload handler
  - Create S3Upload module for generating presigned URLs and handling uploads
- [ ] Build Post LiveViews (3 steps)
  - PostLive.Index - list all published posts with crypto-themed card design
  - PostLive.Form - create/edit posts with Quill editor integration
  - PostLive.Show - display individual post with rendered rich content
- [ ] Update layouts and styling (2 steps)
  - Match root.html.heex to Blockster design (dark theme, crypto aesthetic)
  - Update app.css with custom gradients, colors matching the reference site
  - Update <Layouts.app> component to match design
- [ ] Update router and test (1 step)
  - Add routes for posts index, show, new, edit
  - Remove placeholder home route
  - Visit app to verify everything works
  
Reserved: 2 steps for debugging

## Design Notes
- Dark theme with vibrant accent colors (purple, blue, pink gradients)
- Bold typography with crypto/Web3 aesthetic
- Card-based layouts with hover effects
- Responsive design with mobile considerations

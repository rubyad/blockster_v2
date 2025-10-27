# BlocksterV2 Blog Platform Plan

## Project Overview
Building a crypto/blockchain themed blog platform with rich text editing (Quill.js) and S3 image uploads, matching the exact design from https://blockerstaging2.netlify.app/unregistered-users

## Detailed Implementation Steps

- [x] Generate Phoenix LiveView project with PostgreSQL
- [x] Create detailed plan.md
- [x] Start server and create static mockup
  - Replaced home.html.heex with full static mockup matching the Blockster design
  - Vibrant crypto-themed design with gradients, bold colors, card layouts
- [x] Add AWS S3 dependencies and configuration
  - Added `{:ex_aws, "~> 2.5"}`, `{:ex_aws_s3, "~> 2.5"}`, `{:hackney, "~> 1.20"}`, `{:sweet_xml, "~> 0.7"}`
  - Ready for S3 configuration in config files
  - Need to set up .env instructions for AWS credentials
- [x] Create Blog schemas and migrations
  - Created Post schema with fields: title, slug, content (rich text JSON), excerpt, author_name, published_at, view_count, category
  - Migration created and run successfully
  - Blog context created with CRUD operations
- [x] Set up Quill.js integration (partial)
  - Added Quill.js CDN links to root.html.heex
  - Still need: custom JS hook for Quill editor with S3 image upload handler
  - Still need: S3Upload module for generating presigned URLs and handling uploads
- [x] Build Post LiveViews (partial)
  - PostLive.Index - created for listing published posts
  - PostLive.Show - created for displaying individual posts
  - Still need: PostLive templates (index.html.heex, show.html.heex)
  - Still need: Post form component with Quill editor integration
- [x] Update layouts and styling
  - Matched root.html.heex to Blockster design (dark theme forced)
  - Updated app.css with custom gradients, colors matching the reference site
  - Updated <Layouts.app> component to match design
- [x] Update router
  - Added routes for posts index, show, new, edit
  - Removed placeholder home route
  - Ready to test app

Next steps needed:
- [ ] Create LiveView templates (index.html.heex, show.html.heex)
- [ ] Create Quill editor component with S3 upload
- [ ] Configure S3 settings
- [ ] Test the complete flow

Reserved: 1 step for final verification

## Design Notes
- Dark theme with vibrant accent colors (purple, blue, pink gradients)
- Bold typography with crypto/Web3 aesthetic
- Card-based layouts with hover effects
- Responsive design with mobile considerations


# TipTap Migration Status

## Completed Steps

✅ 1. Installed TipTap npm packages
✅ 2. Created TipTap extensions directory: `assets/js/tiptap_extensions/`
✅ 3. Created Tweet Embed extension: `assets/js/tiptap_extensions/tweet_embed.js`
✅ 4. Created Spacer extension: `assets/js/tiptap_extensions/spacer.js`

## Remaining Steps

### 5. Create Image Upload Extension
Create `assets/js/tiptap_extensions/image_upload.js` - extends @tiptap/extension-image with S3 upload support

### 6. Create Main TipTap Editor Hook
Create `assets/js/tiptap_editor.js` with:
- Editor initialization with all extensions
- Toolbar rendering and event handlers
- Content sync to hidden input
- Tweet/image/spacer insertion handlers

### 7. Update app.js
- Remove: `import Quill from "quill"`
- Remove: `window.Quill = Quill`
- Add: `import { TipTapEditor } from "./tiptap_editor"`
- Change hooks: `QuillEditor` → `TipTapEditor`

### 8. Update CSS (assets/css/app.css)
- Remove lines 5, 635-854 (Quill styles)
- Add TipTap styles for .ProseMirror, .tiptap-toolbar, etc.

### 9. Update Form Template
File: `lib/blockster_v2_web/live/post_live/form_component.html.heex:312-337`
- Change `id="quill-editor"` → `id="tiptap-editor"`
- Change `phx-hook="QuillEditor"` → `phx-hook="TipTapEditor"`
- Add `<div class="tiptap-toolbar"></div>` before editor-container
- Update classes to match TipTap

### 10. Create TipTap Renderer (Backend)
Create `lib/blockster_v2_web/live/post_live/tiptap_renderer.ex` to render TipTap JSON → HTML

### 11. Update show.ex
Modify `render_quill_content` to handle TipTap format

### 12. Delete Old Posts
Run: `mix run -e "BlocksterV2.Repo.delete_all(BlocksterV2.Blog.Post)"`

### 13. Remove Old Files
- Delete: `assets/js/quill_editor.js`
- Run: `npm uninstall quill`

### 14. Test & Deploy
- Test all editor features
- Build assets: `mix assets.build`
- Restart server

## Quick Reference Files

### Extensions Created
- `/Users/tenmerry/Projects/blockster_v2/assets/js/tiptap_extensions/tweet_embed.js`
- `/Users/tenmerry/Projects/blockster_v2/assets/js/tiptap_extensions/spacer.js`

### Files to Modify
- `assets/js/app.js` - Switch to TipTap hook
- `assets/css/app.css` - Replace Quill CSS
- `lib/blockster_v2_web/live/post_live/form_component.html.heex` - Update editor markup
- `lib/blockster_v2_web/live/post_live/show.ex` - Update renderer

### Files to Create
- `assets/js/tiptap_extensions/image_upload.js`
- `assets/js/tiptap_editor.js` (main hook - ~400 lines)
- `lib/blockster_v2_web/live/post_live/tiptap_renderer.ex`

### Files to Delete
- `assets/js/quill_editor.js`

## Next Session Commands

```bash
# Continue migration:
cd /Users/tenmerry/Projects/blockster_v2

# Create remaining extension
# Create main editor hook
# Update files listed above

# Delete all posts
mix run -e "BlocksterV2.Repo.delete_all(BlocksterV2.Blog.Post)"

# Test
mix assets.build && mix phx.server
```

## Notes
- No backward compatibility needed
- All old posts will be deleted
- Fresh start with TipTap format
- Migration est. 4-6 hours remaining

// Quill Editor Hook with S3 Image Upload and Tweet Embeds
export const QuillEditor = {
  mounted() {
    console.log("=== QuillEditor Hook Mounted ===");
    console.log("1. Hook element:", this.el);
    console.log("2. Quill available:", typeof Quill);
    console.log(
      "3. Editor container:",
      this.el.querySelector(".editor-container"),
    );

    const toolbarOptions = [
      ["bold", "italic", "underline", "strike"],
      ["blockquote", "code-block"],
      [{ header: 1 }, { header: 2 }],
      [{ list: "ordered" }, { list: "bullet" }],
      [{ script: "sub" }, { script: "super" }],
      [{ indent: "-1" }, { indent: "+1" }],
      [{ size: ["small", false, "large", "huge"] }],
      [{ header: [1, 2, 3, 4, 5, 6, false] }],
      [{ color: [] }, { background: [] }],
      [{ align: [] }],
      ["link", "image", "tweet"],
      ["clean"],
    ];

    console.log("4. Toolbar options:", toolbarOptions);

    const editorContainer = this.el.querySelector(".editor-container");
    if (!editorContainer) {
      console.error("ERROR: .editor-container not found!");
      return;
    }

    try {
      console.log("5. Creating Quill instance...");
      this.quill = new Quill(editorContainer, {
        theme: "snow",
        modules: {
          toolbar: {
            container: toolbarOptions,
            handlers: {
              image: () => this.imageHandler(),
              tweet: () => this.tweetHandler(),
            },
          },
        },
        placeholder: "Write your post content here...",
      });
      this.el.__quill = this.quill;

      // Register custom tweet embed
      const BlockEmbed = Quill.import("blots/block/embed");

      class TweetEmbed extends BlockEmbed {
        static create(value) {
          const node = super.create();
          node.setAttribute("data-tweet-url", value.url);
          node.setAttribute("data-tweet-id", value.id);
          node.setAttribute("contenteditable", "false");
          node.classList.add("tweet-embed-placeholder");
          node.innerHTML = `
          <div style="padding: 12px; background: #f7f9fa; border: 1px solid #e1e8ed; border-radius: 8px; margin: 12px 0;">
            <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 8px;">
              <svg style="width: 20px; height: 20px; fill: #1DA1F2;" viewBox="0 0 24 24">
                <path d="M23.953 4.57a10 10 0 01-2.825.775 4.958 4.958 0 002.163-2.723c-.951.555-2.005.959-3.127 1.184a4.92 4.92 0 00-8.384 4.482C7.69 8.095 4.067 6.13 1.64 3.162a4.822 4.822 0 00-.666 2.475c0 1.71.87 3.213 2.188 4.096a4.904 4.904 0 01-2.228-.616v.06a4.923 4.923 0 003.946 4.827 4.996 4.996 0 01-2.212.085 4.936 4.936 0 004.604 3.417 9.867 9.867 0 01-6.102 2.105c-.39 0-.779-.023-1.17-.067a13.995 13.995 0 007.557 2.209c9.053 0 13.998-7.496 13.998-13.985 0-.21 0-.42-.015-.63A9.935 9.935 0 0024 4.59z"/>
              </svg>
              <span style="color: #14171a; font-weight: 600; font-size: 14px;">Tweet Embed</span>
            </div>
            <div style="color: #657786; font-size: 13px; word-break: break-all;">
              ${value.url}
            </div>
          </div>
        `;
          return node;
        }

        static value(node) {
          return {
            url: node.getAttribute("data-tweet-url"),
            id: node.getAttribute("data-tweet-id"),
          };
        }
      }

      TweetEmbed.blotName = "tweet";
      TweetEmbed.tagName = "div";
      TweetEmbed.className = "tweet-embed";

      Quill.register(TweetEmbed);
      console.log("✅ TweetEmbed registered with Quill");
      console.log("6. Quill instance created:", this.quill);
    } catch (error) {
      console.error("ERROR creating Quill:", error);
      return;
    }

    // Track if we've loaded initial content
    this.contentLoaded = false;

    // Load initial content if provided
    this.loadContent();

    // Update hidden input on content change
    this.quill.on("text-change", () => {
      console.log("Text changed, syncing...");
      this.syncToHiddenInput();
    });

    console.log("=== QuillEditor Hook Mount Complete ===");
  },

  updated() {
    console.log("=== QuillEditor Hook Updated ===");
    // CRITICAL: Don't reload editor content on updates!
    // The editor maintains its own state and shouldn't be cleared
    // when LiveView re-renders (e.g., during validation or save errors)

    // Only load content on first update if not yet loaded
    if (!this.contentLoaded) {
      console.log("First update - loading initial content");
      this.loadContent();
    } else {
      console.log("Skipping content reload - editor already has content");
    }
  },

  loadContent() {
    console.log("=== Loading Content ===");
    const initialContent = this.el.dataset.content;
    console.log("Initial content:", initialContent);

    if (initialContent && initialContent !== "{}") {
      try {
        const content = JSON.parse(initialContent);
        console.log("Parsed content:", content);
        this.quill.setContents(content);
        this.contentLoaded = true;
        console.log("Content loaded successfully");
      } catch (e) {
        console.error("Failed to parse initial content:", e);
      }
    } else {
      // Mark as loaded even if empty so we don't reload on updates
      this.contentLoaded = true;
      console.log("No initial content to load");
    }
  },

  syncToHiddenInput() {
    const content = this.quill.getContents();
    const hiddenInput = this.el.querySelector('input[type="hidden"]');
    if (hiddenInput) {
      hiddenInput.value = JSON.stringify(content);
      // Trigger change event for LiveView
      hiddenInput.dispatchEvent(new Event("input", { bubbles: true }));
      console.log("Synced to hidden input");
    } else {
      console.error("ERROR: Hidden input not found!");
    }
  },

  imageHandler() {
    console.log("=== Image Handler Called ===");
    const input = document.createElement("input");
    input.setAttribute("type", "file");
    input.setAttribute("accept", "image/*");
    input.click();

    input.onchange = async () => {
      const file = input.files[0];
      if (!file) return;

      console.log("Selected file:", file.name, file.size);

      // Validate file size (max 5MB)
      if (file.size > 5 * 1024 * 1024) {
        alert("Image must be less than 5MB");
        return;
      }

      // Validate file type
      if (!file.type.startsWith("image/")) {
        alert("Please select an image file");
        return;
      }

      try {
        // Show loading state
        const range = this.quill.getSelection(true);
        this.quill.insertText(range.index, "Uploading image...");
        this.quill.setSelection(range.index + 18);

        console.log("Requesting presigned URL...");

        // Request presigned URL from server
        const response = await fetch("/api/s3/presigned-url", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")
              .content,
          },
          body: JSON.stringify({
            filename: file.name,
            content_type: file.type,
          }),
        });

        if (!response.ok) {
          throw new Error("Failed to get upload URL");
        }

        const { upload_url, public_url } = await response.json();
        console.log("Got presigned URL, uploading to S3...");

        // Upload to S3
        const uploadResponse = await fetch(upload_url, {
          method: "PUT",
          body: file,
          headers: {
            "Content-Type": file.type,
          },
        });

        if (!uploadResponse.ok) {
          throw new Error("Failed to upload image");
        }

        console.log("Upload successful, inserting image...");

        // Remove loading text and insert image
        this.quill.deleteText(range.index, 18);
        this.quill.insertEmbed(range.index, "image", public_url);
        this.quill.setSelection(range.index + 1);

        // Sync to hidden input after image upload
        this.syncToHiddenInput();

        console.log("Image inserted successfully");
      } catch (error) {
        console.error("Image upload failed:", error);
        alert("Failed to upload image. Please try again.");
        // Remove loading text on error
        const currentRange = this.quill.getSelection();
        if (currentRange) {
          this.quill.deleteText(currentRange.index - 18, 18);
        }
      }
    };
  },

  tweetHandler() {
    console.log("=== Tweet Handler Called ===");

    // Prompt user for tweet URL
    const tweetUrl = prompt(
      "Enter Twitter/X post URL:\n(e.g., https://twitter.com/username/status/1234567890)",
    );

    if (!tweetUrl) {
      console.log("Tweet embed cancelled");
      return;
    }

    // Validate tweet URL format
    const tweetPattern =
      /^https?:\/\/(twitter\.com|x\.com)\/[\w]+\/status\/(\d+)/;
    const match = tweetUrl.match(tweetPattern);

    if (!match) {
      alert(
        "Invalid tweet URL. Please use format:\nhttps://twitter.com/username/status/1234567890",
      );
      return;
    }

    const tweetId = match[2];
    console.log("Valid tweet URL, ID:", tweetId);

    try {
      // Get current cursor position
      const range = this.quill.getSelection(true);

      // Insert tweet embed as a custom block
      // We'll store it as a special insert with tweet data
      this.quill.insertText(range.index, "\n");
      this.quill.insertEmbed(range.index + 1, "tweet", {
        url: tweetUrl,
        id: tweetId,
      });
      this.quill.insertText(range.index + 2, "\n");
      this.quill.setSelection(range.index + 3);

      // Sync to hidden input
      this.syncToHiddenInput();

      console.log("Tweet embed inserted successfully");
    } catch (error) {
      console.error("Failed to insert tweet:", error);
      alert("Failed to insert tweet. Please try again.");
    }
  },

  destroyed() {
    console.log("=== QuillEditor Hook Destroyed ===");
    if (this.quill) {
      this.quill = null;
    }
  },
};

// Quill Editor Hook with S3 Image Upload and Tweet Embeds
export const QuillEditor = {
  mounted() {
    // Register custom tweet embed format
    const BlockEmbed = Quill.import("blots/block/embed");

    class TweetBlot extends BlockEmbed {
      static create(value) {
        const node = super.create();
        node.setAttribute("data-tweet-id", value);
        node.setAttribute("contenteditable", "false");
        node.className = "tweet-embed-placeholder";
        node.innerHTML = `
          <div style="border: 2px dashed #1DA1F2; padding: 20px; border-radius: 8px; background: #F7F9FA; text-align: center; color: #1DA1F2; font-family: system-ui, -apple-system, sans-serif;">
            <svg style="width: 24px; height: 24px; display: inline-block; margin-bottom: 8px;" viewBox="0 0 24 24" fill="#1DA1F2">
              <path d="M23.953 4.57a10 10 0 01-2.825.775 4.958 4.958 0 002.163-2.723c-.951.555-2.005.959-3.127 1.184a4.92 4.92 0 00-8.384 4.482C7.69 8.095 4.067 6.13 1.64 3.162a4.822 4.822 0 00-.666 2.475c0 1.71.87 3.213 2.188 4.096a4.904 4.904 0 01-2.228-.616v.06a4.923 4.923 0 003.946 4.827 4.996 4.996 0 01-2.212.085 4.936 4.936 0 004.604 3.417 9.867 9.867 0 01-6.102 2.105c-.39 0-.779-.023-1.17-.067a13.995 13.995 0 007.557 2.209c9.053 0 13.998-7.496 13.998-13.985 0-.21 0-.42-.015-.63A9.935 9.935 0 0024 4.59z"/>
            </svg>
            <div style="font-size: 14px; font-weight: 600;">Tweet Embed</div>
            <div style="font-size: 12px; color: #657786; margin-top: 4px;">ID: ${value}</div>
          </div>
        `;
        return node;
      }

      static value(node) {
        return node.getAttribute("data-tweet-id");
      }
    }

    TweetBlot.blotName = "tweet";
    TweetBlot.tagName = "div";
    TweetBlot.className = "tweet-embed";

    Quill.register(TweetBlot);

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

    this.quill = new Quill(this.el.querySelector(".editor-container"), {
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

    // Track if we've loaded initial content
    this.contentLoaded = false;

    // Load initial content if provided
    this.loadContent();

    // Update hidden input on content change
    this.quill.on("text-change", () => {
      this.syncToHiddenInput();
    });
  },

  updated() {
    // CRITICAL: Don't reload editor during normal edits!
    // Only reload on initial mount or when explicitly switching posts
    // This prevents the editor from clearing when user applies formatting

    // If we've already loaded content, don't reload unless explicitly needed
    if (this.contentLoaded) {
      return;
    }

    // Only load content on first update if not yet loaded
    this.loadContent();
  },

  loadContent() {
    const initialContent = this.el.dataset.content;
    if (initialContent && initialContent !== "{}") {
      try {
        const content = JSON.parse(initialContent);
        this.quill.setContents(content);
        this.contentLoaded = true;
      } catch (e) {
        console.error("Failed to parse initial content:", e);
      }
    }
  },

  syncToHiddenInput() {
    const content = this.quill.getContents();
    const hiddenInput = this.el.querySelector('input[type="hidden"]');
    if (hiddenInput) {
      hiddenInput.value = JSON.stringify(content);
      // Trigger change event for LiveView
      hiddenInput.dispatchEvent(new Event("input", { bubbles: true }));
    }
  },

  tweetHandler() {
    const tweetUrl = prompt(
      "Enter Twitter/X tweet URL:\n(e.g., https://twitter.com/user/status/1234567890)",
    );

    if (!tweetUrl) return;

    // Extract tweet ID from various Twitter URL formats
    const tweetId = this.extractTweetId(tweetUrl);

    if (!tweetId) {
      alert(
        "Invalid tweet URL. Please enter a valid Twitter/X URL.\n\nExamples:\n• https://twitter.com/user/status/1234567890\n• https://x.com/user/status/1234567890",
      );
      return;
    }

    // Insert tweet embed at current cursor position
    const range = this.quill.getSelection(true);
    this.quill.insertEmbed(range.index, "tweet", tweetId);
    this.quill.setSelection(range.index + 1);

    // Sync to hidden input after tweet insertion
    this.syncToHiddenInput();
  },

  extractTweetId(url) {
    // Handle various Twitter/X URL formats:
    // https://twitter.com/username/status/1234567890
    // https://x.com/username/status/1234567890
    // https://twitter.com/username/status/1234567890?s=20
    // https://mobile.twitter.com/username/status/1234567890

    const patterns = [
      /(?:twitter\.com|x\.com)\/\w+\/status\/(\d+)/,
      /mobile\.twitter\.com\/\w+\/status\/(\d+)/,
    ];

    for (const pattern of patterns) {
      const match = url.match(pattern);
      if (match && match[1]) {
        return match[1];
      }
    }

    // If it's just a number, assume it's already a tweet ID
    if (/^\d+$/.test(url.trim())) {
      return url.trim();
    }

    return null;
  },

  imageHandler() {
    const input = document.createElement("input");
    input.setAttribute("type", "file");
    input.setAttribute("accept", "image/*");
    input.click();

    input.onchange = async () => {
      const file = input.files[0];
      if (!file) return;

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

        // Remove loading text and insert image
        this.quill.deleteText(range.index, 18);
        this.quill.insertEmbed(range.index, "image", public_url);
        this.quill.setSelection(range.index + 1);

        // Sync to hidden input after image upload
        this.syncToHiddenInput();
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

  destroyed() {
    if (this.quill) {
      this.quill = null;
    }
  },
};

// Quill Editor Hook with S3 Image Upload
export const QuillEditor = {
  mounted() {
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
      ["link", "image"],
      ["clean"],
    ];

    this.quill = new Quill(this.el.querySelector(".editor-container"), {
      theme: "snow",
      modules: {
        toolbar: {
          container: toolbarOptions,
          handlers: {
            image: () => this.imageHandler(),
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

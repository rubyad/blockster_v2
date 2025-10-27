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

    // Load initial content if provided
    this.loadContent();

    // Update hidden input on content change
    this.quill.on("text-change", () => {
      this.syncToHiddenInput();
    });
  },

  updated() {
    // Prevent reloading content unless it truly changed from the server
    // This avoids clearing the editor when user makes formatting changes
    const newContent = this.el.dataset.content;

    // Skip update if no new content from server
    if (!newContent || newContent === "{}") {
      return;
    }

    // Get current editor content
    const currentContent = this.quill.getContents();

    // Only reload if the content structure actually changed
    // Don't reload on every LiveView update - only when server sends new content
    try {
      const serverContent = JSON.parse(newContent);

      // Deep comparison of ops arrays
      const currentOps = JSON.stringify(currentContent.ops);
      const serverOps = JSON.stringify(serverContent.ops);

      // Only reload if content is truly different
      if (
        currentOps !== serverOps &&
        serverContent.ops &&
        serverContent.ops.length > 0
      ) {
        const currentSelection = this.quill.getSelection();
        this.quill.setContents(serverContent);

        // Restore cursor position if it existed
        if (currentSelection) {
          this.quill.setSelection(currentSelection);
        }
      }
    } catch (e) {
      console.error("Failed to compare content:", e);
    }
  },

  loadContent() {
    const initialContent = this.el.dataset.content;
    if (initialContent && initialContent !== "{}") {
      try {
        const content = JSON.parse(initialContent);
        this.quill.setContents(content);
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

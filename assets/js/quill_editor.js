// Quill Editor Hook with S3 Image Upload
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
      ["link", "image"],
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
    this.el.__quill = this.quill;
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

  destroyed() {
    console.log("=== QuillEditor Hook Destroyed ===");
    if (this.quill) {
      this.quill = null;
    }
  },
};

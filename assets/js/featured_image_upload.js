// Featured Image Upload Hook for S3
export const FeaturedImageUpload = {
  mounted() {
    this.el.addEventListener("change", async (e) => {
      const file = e.target.files[0];
      if (!file) return;

      // Validate file size (max 5MB)
      if (file.size > 5 * 1024 * 1024) {
        alert("Image must be less than 5MB");
        e.target.value = ""; // Clear the input
        return;
      }

      // Validate file type
      if (!file.type.startsWith("image/")) {
        alert("Please select an image file");
        e.target.value = ""; // Clear the input
        return;
      }

      try {
        // Show loading state
        const uploadButton = document.querySelector(
          'button[onclick*="featured-image-input"]',
        );
        if (uploadButton) {
          uploadButton.disabled = true;
          uploadButton.innerHTML =
            '<svg class="animate-spin h-5 w-5 inline mr-2" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg>Uploading...';
        }

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

        // Update the hidden input directly (no LiveView event!)
        const hiddenInput = document.querySelector(
          'input[name="post[featured_image]"]',
        );
        if (hiddenInput) {
          hiddenInput.value = public_url;
        }

        // Show preview image by creating/updating the preview div
        const uploadSection = this.el.closest("div").parentElement;
        let previewDiv = uploadSection.querySelector(".image-preview");

        if (!previewDiv) {
          // Create preview div if it doesn't exist
          previewDiv = document.createElement("div");
          previewDiv.className = "image-preview mb-3";
          previewDiv.innerHTML = `
            <img src="${public_url}" alt="Featured image preview" class="w-full max-w-md h-48 object-cover rounded-lg border border-white/20" />
            <button type="button" class="remove-image mt-2 text-sm text-red-400 hover:text-red-300 transition-colors">
              Remove image
            </button>
          `;

          // Insert before the upload button section
          const uploadButtonDiv = uploadSection.querySelector(".flex.gap-3");
          uploadSection.insertBefore(previewDiv, uploadButtonDiv);

          // Add remove handler
          previewDiv
            .querySelector(".remove-image")
            .addEventListener("click", () => {
              hiddenInput.value = "";
              previewDiv.remove();
              if (uploadButton) {
                uploadButton.innerHTML =
                  '<svg class="w-5 h-5 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path></svg>Upload Image';
              }
            });
        } else {
          // Update existing preview
          previewDiv.querySelector("img").src = public_url;
        }

        // Reset button state
        if (uploadButton) {
          uploadButton.disabled = false;
          uploadButton.innerHTML =
            '<svg class="w-5 h-5 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path></svg>Change Image';
        }

        // Clear the file input
        e.target.value = "";
      } catch (error) {
        console.error("Featured image upload failed:", error);
        alert("Failed to upload image. Please try again.");

        // Reset button state on error
        const uploadButton = document.querySelector(
          'button[onclick*="featured-image-input"]',
        );
        if (uploadButton) {
          uploadButton.disabled = false;
          uploadButton.innerHTML =
            '<svg class="w-5 h-5 inline mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path></svg>Upload Image';
        }

        // Clear the file input
        e.target.value = "";
      }
    });
  },
};

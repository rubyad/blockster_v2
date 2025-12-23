// Artist Image Upload Hook for S3
// Uploads image to S3 and converts to ImageKit URL
export const ArtistImageUpload = {
  mounted() {
    this.el.addEventListener("change", async (e) => {
      const file = e.target.files[0];
      if (!file) return;

      // Validate file size (max 5MB)
      if (file.size > 5 * 1024 * 1024) {
        alert("Image must be less than 5MB");
        e.target.value = "";
        return;
      }

      // Validate file type
      if (!file.type.startsWith("image/")) {
        alert("Please select an image file");
        e.target.value = "";
        return;
      }

      try {
        // Get the container and elements
        const container = this.el.closest(".artist-image-upload");
        const previewContainer = container ? container.querySelector(".image-preview-container") : null;
        const statusEl = container ? container.querySelector(".upload-status") : null;
        const hiddenInput = container ? container.querySelector('input[name="artist[image]"]') : null;

        // Show loading state
        if (statusEl) {
          statusEl.textContent = "Uploading...";
          statusEl.classList.remove("hidden");
        }

        console.log("Starting S3 upload for artist image:", file.name);

        // Request presigned URL from server
        const response = await fetch("/api/s3/presigned-url", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
          },
          body: JSON.stringify({
            filename: file.name,
            content_type: file.type,
          }),
        });

        if (!response.ok) {
          throw new Error("Failed to get upload URL from server");
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
          throw new Error("Failed to upload image to S3");
        }

        console.log("Upload successful! S3 URL:", public_url);

        // Convert S3 URL to ImageKit URL
        // S3: https://bucket.s3.region.amazonaws.com/uploads/timestamp-random.ext
        // ImageKit: https://ik.imagekit.io/blockster/uploads/timestamp-random.ext
        const imagekitUrl = this.convertToImageKitUrl(public_url);
        console.log("ImageKit URL:", imagekitUrl);

        // Update the hidden input with ImageKit URL
        if (hiddenInput) {
          hiddenInput.value = imagekitUrl;
          // Trigger change event to ensure form sees the new value
          hiddenInput.dispatchEvent(new Event('input', { bubbles: true }));
        }

        // Update preview image
        if (previewContainer) {
          previewContainer.innerHTML = `<img src="${imagekitUrl}" class="w-20 h-20 rounded-full object-cover border border-gray-300" alt="Artist preview" />`;
        }

        // Update status
        if (statusEl) {
          statusEl.textContent = "Uploaded!";
          statusEl.classList.remove("text-gray-500");
          statusEl.classList.add("text-green-600");
          setTimeout(() => {
            statusEl.classList.add("hidden");
            statusEl.classList.remove("text-green-600");
            statusEl.classList.add("text-gray-500");
          }, 2000);
        }

        // Clear the file input
        e.target.value = "";

      } catch (error) {
        console.error("Artist image upload failed:", error);
        alert(`Failed to upload image: ${error.message}`);

        const container = this.el.closest(".artist-image-upload");
        const statusEl = container ? container.querySelector(".upload-status") : null;
        if (statusEl) {
          statusEl.textContent = "Upload failed";
          statusEl.classList.remove("text-gray-500");
          statusEl.classList.add("text-red-600");
          setTimeout(() => {
            statusEl.classList.add("hidden");
            statusEl.classList.remove("text-red-600");
            statusEl.classList.add("text-gray-500");
          }, 2000);
        }

        e.target.value = "";
      }
    });
  },

  // Convert S3 URL to ImageKit URL
  convertToImageKitUrl(s3Url) {
    const imagekitBase = "https://ik.imagekit.io/blockster";

    // Extract path from S3 URL
    // S3 URL format: https://bucket.s3.region.amazonaws.com/path/filename.ext
    const match = s3Url.match(/\.amazonaws\.com\/(.+)$/);
    if (match && match[1]) {
      return `${imagekitBase}/${match[1]}`;
    }

    // If can't parse, return original URL
    return s3Url;
  }
};

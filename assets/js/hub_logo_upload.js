// Hub Logo Upload Hook for S3
export const HubLogoUpload = {
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
        // Get the preview image element
        const container = this.el.closest(".img-rounded") || this.el.parentElement;
        const previewImg = container.querySelector("img");

        // Show loading state on the image
        if (previewImg) {
          previewImg.style.opacity = "0.5";
        }

        console.log("Starting S3 upload for hub logo:", file.name);

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

        console.log("Presigned URL response status:", response.status);

        if (!response.ok) {
          const errorData = await response.text();
          console.error("Failed to get presigned URL:", errorData);
          throw new Error("Failed to get upload URL from server");
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

        console.log("S3 upload response status:", uploadResponse.status);

        if (!uploadResponse.ok) {
          const errorText = await uploadResponse.text();
          console.error("S3 upload failed:", errorText);
          throw new Error("Failed to upload image to S3");
        }

        console.log("Upload successful! Public URL:", public_url);

        // Update preview image immediately
        if (previewImg) {
          previewImg.src = public_url;
          previewImg.style.opacity = "1";
        }

        // Push event to LiveView to save the logo URL
        this.pushEvent("update_hub_logo", { logo_url: public_url });

        // Clear the file input
        e.target.value = "";

        console.log("Hub logo upload complete!");
      } catch (error) {
        console.error("Hub logo upload failed:", error);
        alert(`Failed to upload image: ${error.message}`);

        // Reset preview opacity
        const container = this.el.closest(".img-rounded") || this.el.parentElement;
        const previewImg = container.querySelector("img");
        if (previewImg) {
          previewImg.style.opacity = "1";
        }

        // Clear the file input
        e.target.value = "";
      }
    });
  },
};

// Hub Logo Upload for Form Component (updates hidden input + preview)
export const HubLogoFormUpload = {
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
        // Get the container and status elements
        const container = this.el.closest(".logo-upload-container");
        const statusEl = container ? container.querySelector(".upload-status") : null;

        // Show loading state
        if (statusEl) {
          statusEl.textContent = "Uploading...";
          statusEl.classList.remove("hidden");
        }

        console.log("Starting S3 upload for hub logo:", file.name);

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

        console.log("Upload successful! Public URL:", public_url);

        // Update the hidden input
        const hiddenInput = container ? container.querySelector('input[name="hub[logo_url]"]') : document.querySelector('input[name="hub[logo_url]"]');
        if (hiddenInput) {
          hiddenInput.value = public_url;
        }

        // Update preview image - replace placeholder div with img if needed
        const previewContainer = container ? container.querySelector(".flex-shrink-0") : null;
        if (previewContainer) {
          // Replace entire preview content with an img
          previewContainer.innerHTML = `<img src="${public_url}" class="logo-preview h-20 w-20 rounded-full object-cover border border-gray-200" alt="Logo preview" />`;
        }

        // Update status
        if (statusEl) {
          statusEl.textContent = "Uploaded!";
          setTimeout(() => {
            statusEl.classList.add("hidden");
          }, 2000);
        }

        // Clear the file input
        e.target.value = "";

      } catch (error) {
        console.error("Hub logo upload failed:", error);
        alert(`Failed to upload image: ${error.message}`);

        const container = this.el.closest(".logo-upload-container");
        const statusEl = container ? container.querySelector(".upload-status") : null;
        if (statusEl) {
          statusEl.textContent = "Upload failed";
          setTimeout(() => {
            statusEl.classList.add("hidden");
          }, 2000);
        }

        e.target.value = "";
      }
    });
  },
};

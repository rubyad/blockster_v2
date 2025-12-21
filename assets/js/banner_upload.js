// Banner Upload Hook for S3 with ImageKit transformation
export const BannerUpload = {
  mounted() {
    this.el.addEventListener("change", async (e) => {
      const file = e.target.files[0];
      if (!file) return;

      // Validate file size (max 25MB for banners)
      if (file.size > 25 * 1024 * 1024) {
        alert("Image must be less than 25MB");
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
        const targetSelector = this.el.dataset.target;
        const bannerKey = this.el.dataset.bannerKey;
        const targetSection = document.querySelector(targetSelector);
        const bannerImg = targetSection ? targetSection.querySelector("img") : null;

        // Show loading state
        if (bannerImg) {
          bannerImg.style.opacity = "0.5";
        }

        console.log("Starting S3 upload for banner:", file.name);

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
          throw new Error("Failed to upload image to S3");
        }

        console.log("Upload successful! Public URL:", public_url);

        // Convert S3 URL to ImageKit URL for optimization
        const imagekitUrl = convertToImageKitUrl(public_url);
        console.log("ImageKit URL:", imagekitUrl);

        // Update preview image immediately with ImageKit transformation
        if (bannerImg) {
          bannerImg.src = imagekitUrl + "?tr=w-1920,q-90";
          bannerImg.style.opacity = "1";
        }

        // Push event to LiveView component to save the URL
        // We save the base ImageKit URL without transformations
        this.pushEventTo(targetSelector, "update_banner", { banner_url: imagekitUrl });

        // Clear the file input
        e.target.value = "";

        console.log("Banner upload complete!");
      } catch (error) {
        console.error("Banner upload failed:", error);
        alert(`Failed to upload image: ${error.message}`);

        // Reset preview opacity
        const targetSelector = this.el.dataset.target;
        const targetSection = document.querySelector(targetSelector);
        const bannerImg = targetSection ? targetSection.querySelector("img") : null;
        if (bannerImg) {
          bannerImg.style.opacity = "1";
        }

        // Clear the file input
        e.target.value = "";
      }
    });
  },
};

// Convert S3 URL to ImageKit URL
function convertToImageKitUrl(s3Url) {
  // Expected S3 URL format: https://blockster-uploads.s3.amazonaws.com/uploads/...
  // or https://blockster-uploads.s3.us-east-2.amazonaws.com/uploads/...
  // Convert to: https://ik.imagekit.io/blockster/...

  try {
    const url = new URL(s3Url);
    const pathname = url.pathname;

    // Extract the path after 'uploads/' if present
    const uploadsIndex = pathname.indexOf('/uploads/');
    if (uploadsIndex !== -1) {
      const relativePath = pathname.substring(uploadsIndex + 1); // includes 'uploads/'
      return `https://ik.imagekit.io/blockster/${relativePath}`;
    }

    // If no 'uploads/' prefix, just use the path
    return `https://ik.imagekit.io/blockster${pathname}`;
  } catch (error) {
    console.error("Failed to convert S3 URL to ImageKit URL:", error);
    // Return original URL as fallback
    return s3Url;
  }
}

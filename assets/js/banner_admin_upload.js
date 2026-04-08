// BannerAdminUpload — uploads an image (incl. GIFs) to S3 via presigned URL,
// converts to ImageKit URL, then writes the URL into a hidden input and
// updates a preview <img>.
//
// Usage in template:
//   <input type="file" phx-hook="BannerAdminUpload"
//          data-input="banner_image_url_input"   id="banner_image_file"
//          data-preview="banner_image_preview"   accept="image/*" />
//   <input type="hidden" id="banner_image_url_input" name="banner[image_url]" value={...} />
//   <img id="banner_image_preview" src={...} />
//
// Both data-input and data-preview reference element IDs.

export const BannerAdminUpload = {
  mounted() {
    this.el.addEventListener("change", async (e) => {
      const file = e.target.files[0];
      if (!file) return;

      // 25 MB max — generous for animated GIFs
      if (file.size > 25 * 1024 * 1024) {
        alert("Image must be less than 25MB");
        e.target.value = "";
        return;
      }

      if (!file.type.startsWith("image/")) {
        alert("Please select an image file");
        e.target.value = "";
        return;
      }

      const hiddenInputId = this.el.dataset.input;
      const previewId = this.el.dataset.preview;
      const hiddenInput = hiddenInputId ? document.getElementById(hiddenInputId) : null;
      const previewImg = previewId ? document.getElementById(previewId) : null;

      // Loading state
      const originalLabel = this.el.previousElementSibling;
      if (previewImg) previewImg.style.opacity = "0.5";

      try {
        const csrf = document.querySelector("meta[name='csrf-token']").content;

        const presignRes = await fetch("/api/s3/presigned-url", {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
          body: JSON.stringify({ filename: file.name, content_type: file.type }),
        });

        if (!presignRes.ok) throw new Error("Failed to get upload URL");
        const { upload_url, public_url } = await presignRes.json();

        const uploadRes = await fetch(upload_url, {
          method: "PUT",
          body: file,
          headers: { "Content-Type": file.type },
        });
        if (!uploadRes.ok) throw new Error("Failed to upload image to S3");

        const finalUrl = convertToImageKitUrl(public_url);

        if (hiddenInput) {
          hiddenInput.value = finalUrl;
          // Trigger phx-change so LiveView form sees the new value
          hiddenInput.dispatchEvent(new Event("input", { bubbles: true }));
        }

        if (previewImg) {
          previewImg.src = finalUrl;
          previewImg.style.opacity = "1";
          previewImg.classList.remove("hidden");
        }

        e.target.value = "";
      } catch (err) {
        console.error("Banner upload failed:", err);
        alert(`Failed to upload image: ${err.message}`);
        if (previewImg) previewImg.style.opacity = "1";
        e.target.value = "";
      }
    });
  },
};

// Convert S3 URL to ImageKit URL
function convertToImageKitUrl(s3Url) {
  try {
    const url = new URL(s3Url);
    const pathname = url.pathname;
    const uploadsIndex = pathname.indexOf("/uploads/");
    if (uploadsIndex !== -1) {
      const relativePath = pathname.substring(uploadsIndex + 1);
      return `https://ik.imagekit.io/blockster/${relativePath}`;
    }
    return `https://ik.imagekit.io/blockster${pathname}`;
  } catch (_e) {
    return s3Url;
  }
}

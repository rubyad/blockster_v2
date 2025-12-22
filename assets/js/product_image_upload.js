// Product Image Upload Hook for S3 - supports multiple images
export const ProductImageUpload = {
  mounted() {
    this.el.addEventListener("change", async (e) => {
      const files = Array.from(e.target.files);
      if (files.length === 0) return;

      for (const file of files) {
        // Validate file type
        if (!file.type.startsWith("image/")) {
          alert(`"${file.name}" is not an image file`);
          continue;
        }

        try {
          console.log("Starting S3 upload for:", file.name);

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

          // Notify LiveView of successful upload
          this.pushEvent("image_uploaded", { url: public_url });

          console.log("Upload complete for:", file.name);
        } catch (error) {
          console.error("Product image upload failed:", error);
          console.error("Error stack:", error.stack);
          alert(`Failed to upload image "${file.name}": ${error.message}`);
        }
      }

      // Clear the file input
      e.target.value = "";
    });
  },
};

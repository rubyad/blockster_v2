// Featured Image Upload Hook for Content Automation edit page
// Uploads to S3 via presigned URL, then pushes the public URL to LiveView
export const ContentFeaturedImageUpload = {
  mounted() {
    this.el.addEventListener("change", async (e) => {
      const file = e.target.files[0]
      if (!file) return

      if (file.size > 5 * 1024 * 1024) {
        alert("Image must be less than 5MB")
        e.target.value = ""
        return
      }

      if (!file.type.startsWith("image/")) {
        alert("Please select an image file")
        e.target.value = ""
        return
      }

      const btn = document.getElementById("content-featured-image-btn")
      const originalText = btn ? btn.innerHTML : ""

      try {
        if (btn) {
          btn.disabled = true
          btn.innerHTML = '<svg class="animate-spin h-4 w-4 inline mr-2" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg>Uploading...'
        }

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
        })

        if (!response.ok) throw new Error("Failed to get upload URL")

        const { upload_url, public_url } = await response.json()

        const uploadResponse = await fetch(upload_url, {
          method: "PUT",
          body: file,
          headers: { "Content-Type": file.type },
        })

        if (!uploadResponse.ok) throw new Error("Failed to upload image")

        // Push the URL to LiveView
        this.pushEvent("set_featured_image", { url: public_url })
      } catch (error) {
        console.error("Featured image upload failed:", error)
        alert("Failed to upload image: " + error.message)
      } finally {
        if (btn) {
          btn.disabled = false
          btn.innerHTML = originalText
        }
        e.target.value = ""
      }
    })
  },
}

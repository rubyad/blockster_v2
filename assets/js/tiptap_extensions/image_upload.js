import { Image } from '@tiptap/extension-image'

export const ImageUpload = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      uploading: {
        default: false,
      },
    }
  },

  addCommands() {
    return {
      ...this.parent?.(),
      uploadImage: () => ({ commands, editor }) => {
        return new Promise((resolve) => {
          const input = document.createElement('input')
          input.setAttribute('type', 'file')
          input.setAttribute('accept', 'image/*')

          input.onchange = async () => {
            const file = input.files?.[0]
            if (!file) {
              resolve(false)
              return
            }

            // Validate file size (max 5MB)
            if (file.size > 5 * 1024 * 1024) {
              alert('Image must be less than 5MB')
              resolve(false)
              return
            }

            // Validate file type
            if (!file.type.startsWith('image/')) {
              alert('Please select an image file')
              resolve(false)
              return
            }

            try {
              // Insert loading placeholder
              const { from } = editor.state.selection
              editor.commands.insertContent('Uploading image...')

              // Request presigned URL from server
              const response = await fetch('/api/s3/presigned-url', {
                method: 'POST',
                headers: {
                  'Content-Type': 'application/json',
                  'X-CSRF-Token': document.querySelector("meta[name='csrf-token']").content,
                },
                body: JSON.stringify({
                  filename: file.name,
                  content_type: file.type,
                }),
              })

              if (!response.ok) {
                throw new Error('Failed to get upload URL')
              }

              const { upload_url, public_url } = await response.json()

              // Upload to S3
              const uploadResponse = await fetch(upload_url, {
                method: 'PUT',
                body: file,
                headers: {
                  'Content-Type': file.type,
                },
              })

              if (!uploadResponse.ok) {
                throw new Error('Failed to upload image')
              }

              // Remove loading text and insert image
              editor.commands.deleteRange({
                from: from,
                to: from + 'Uploading image...'.length
              })

              editor.commands.setImage({ src: public_url })

              resolve(true)
            } catch (error) {
              console.error('Image upload failed:', error)
              alert('Failed to upload image. Please try again.')

              // Try to remove loading text on error
              try {
                const { from } = editor.state.selection
                editor.commands.deleteRange({
                  from: from - 'Uploading image...'.length,
                  to: from
                })
              } catch (e) {
                // Ignore cleanup errors
              }

              resolve(false)
            }
          }

          input.click()
        })
      },
    }
  },
})

import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import Underline from '@tiptap/extension-underline'
import Placeholder from '@tiptap/extension-placeholder'

export const ProductDescriptionEditor = {
  mounted() {
    console.log("=== ProductDescriptionEditor Hook Mounted ===")

    const editorContainer = this.el.querySelector('.product-editor-container')
    if (!editorContainer) {
      console.error("ERROR: .product-editor-container not found!")
      return
    }

    // Create toolbar
    this.createToolbar()

    // Initialize TipTap editor with basic formatting
    this.editor = new Editor({
      element: editorContainer,
      extensions: [
        StarterKit.configure({
          heading: {
            levels: [2, 3],
          },
        }),
        Link.configure({
          openOnClick: false,
          HTMLAttributes: {
            target: '_blank',
            rel: 'noopener noreferrer',
          },
        }),
        Underline,
        Placeholder.configure({
          placeholder: 'Enter product description...',
        }),
      ],
      editorProps: {
        attributes: {
          class: 'prose prose-sm max-w-none focus:outline-none min-h-[150px] p-3',
        },
      },
      onUpdate: () => {
        this.syncToHiddenInput()
      },
      onCreate: ({ editor }) => {
        // Load content after editor is fully initialized
        setTimeout(() => {
          this.loadContent()
        }, 50)
      },
    })

    // Store editor reference
    this.el.__tiptap = this.editor

    console.log("=== ProductDescriptionEditor Hook Mount Complete ===")
  },

  createToolbar() {
    const toolbar = this.el.querySelector('.product-editor-toolbar')
    if (!toolbar) return

    toolbar.innerHTML = `
      <div class="flex flex-wrap gap-1 p-2 border-b border-gray-200 bg-gray-50">
        <button type="button" data-action="bold" title="Bold (Ctrl+B)" class="px-2 py-1 rounded text-sm hover:bg-gray-200 transition-colors">
          <strong>B</strong>
        </button>
        <button type="button" data-action="italic" title="Italic (Ctrl+I)" class="px-2 py-1 rounded text-sm hover:bg-gray-200 transition-colors">
          <em>I</em>
        </button>
        <button type="button" data-action="underline" title="Underline (Ctrl+U)" class="px-2 py-1 rounded text-sm hover:bg-gray-200 transition-colors">
          <u>U</u>
        </button>
        <span class="w-px h-6 bg-gray-300 mx-1"></span>
        <button type="button" data-action="heading2" title="Heading" class="px-2 py-1 rounded text-sm hover:bg-gray-200 transition-colors font-bold">
          H2
        </button>
        <button type="button" data-action="heading3" title="Subheading" class="px-2 py-1 rounded text-sm hover:bg-gray-200 transition-colors font-bold">
          H3
        </button>
        <span class="w-px h-6 bg-gray-300 mx-1"></span>
        <button type="button" data-action="bulletList" title="Bullet List" class="px-2 py-1 rounded text-sm hover:bg-gray-200 transition-colors">
          • List
        </button>
        <button type="button" data-action="orderedList" title="Numbered List" class="px-2 py-1 rounded text-sm hover:bg-gray-200 transition-colors">
          1. List
        </button>
        <span class="w-px h-6 bg-gray-300 mx-1"></span>
        <button type="button" data-action="link" title="Add Link" class="px-2 py-1 rounded text-sm hover:bg-gray-200 transition-colors">
          Link
        </button>
      </div>
    `

    // Add event listeners
    toolbar.querySelectorAll('button').forEach(button => {
      button.addEventListener('click', (e) => {
        e.preventDefault()
        const action = button.dataset.action
        this.handleToolbarAction(action)
      })
    })

    // Update button states on selection change
    this.updateToolbarState = () => {
      toolbar.querySelectorAll('button').forEach(button => {
        const action = button.dataset.action
        const isActive = this.isFormatActive(action)
        if (isActive) {
          button.classList.add('bg-blue-100', 'text-blue-700')
        } else {
          button.classList.remove('bg-blue-100', 'text-blue-700')
        }
      })
    }

    if (this.editor) {
      this.editor.on('selectionUpdate', this.updateToolbarState)
      this.editor.on('update', this.updateToolbarState)
    }
  },

  handleToolbarAction(action) {
    if (!this.editor) return

    switch (action) {
      case 'bold':
        this.editor.chain().focus().toggleBold().run()
        break
      case 'italic':
        this.editor.chain().focus().toggleItalic().run()
        break
      case 'underline':
        this.editor.chain().focus().toggleUnderline().run()
        break
      case 'heading2':
        this.editor.chain().focus().toggleHeading({ level: 2 }).run()
        break
      case 'heading3':
        this.editor.chain().focus().toggleHeading({ level: 3 }).run()
        break
      case 'bulletList':
        this.editor.chain().focus().toggleBulletList().run()
        break
      case 'orderedList':
        this.editor.chain().focus().toggleOrderedList().run()
        break
      case 'link':
        this.linkHandler()
        break
    }

    this.updateToolbarState()
  },

  isFormatActive(action) {
    if (!this.editor) return false

    switch (action) {
      case 'bold':
        return this.editor.isActive('bold')
      case 'italic':
        return this.editor.isActive('italic')
      case 'underline':
        return this.editor.isActive('underline')
      case 'heading2':
        return this.editor.isActive('heading', { level: 2 })
      case 'heading3':
        return this.editor.isActive('heading', { level: 3 })
      case 'bulletList':
        return this.editor.isActive('bulletList')
      case 'orderedList':
        return this.editor.isActive('orderedList')
      case 'link':
        return this.editor.isActive('link')
      default:
        return false
    }
  },

  linkHandler() {
    const previousUrl = this.editor.getAttributes('link').href
    const url = prompt('Enter URL:', previousUrl || 'https://')

    if (url === null) {
      return // User cancelled
    }

    if (url === '') {
      this.editor.chain().focus().unsetLink().run()
      return
    }

    this.editor.chain().focus().setLink({ href: url }).run()
  },

  loadContent() {
    const hiddenInput = this.el.querySelector('textarea[data-product-description]')
    if (!hiddenInput) return

    const htmlContent = hiddenInput.value
    console.log('Loading HTML content:', htmlContent ? htmlContent.substring(0, 100) + '...' : 'empty')

    if (htmlContent && htmlContent.trim()) {
      this.editor.commands.setContent(htmlContent)
    }
  },

  syncToHiddenInput() {
    const htmlContent = this.editor.getHTML()
    const hiddenInput = this.el.querySelector('textarea[data-product-description]')

    if (hiddenInput) {
      hiddenInput.value = htmlContent
      hiddenInput.dispatchEvent(new Event('input', { bubbles: true }))
    }
  },

  updated() {
    // Don't reload content on updates - this prevents cursor jumping
  },

  destroyed() {
    if (this.editor) {
      this.editor.destroy()
    }
  },
}

import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import Underline from '@tiptap/extension-underline'
import TextAlign from '@tiptap/extension-text-align'
import Placeholder from '@tiptap/extension-placeholder'
import { TweetEmbed } from './tiptap_extensions/tweet_embed'
import { Spacer } from './tiptap_extensions/spacer'
import { ImageUpload } from './tiptap_extensions/image_upload'

export const TipTapEditor = {
  mounted() {
    console.log("=== TipTapEditor Hook Mounted ===")

    const editorContainer = this.el.querySelector('.editor-container')
    if (!editorContainer) {
      console.error("ERROR: .editor-container not found!")
      return
    }

    // Create toolbar
    this.createToolbar()

    // Initialize TipTap editor
    this.editor = new Editor({
      element: editorContainer,
      extensions: [
        StarterKit.configure({
          heading: {
            levels: [1, 2, 3],
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
        TextAlign.configure({
          types: ['heading', 'paragraph'],
        }),
        Placeholder.configure({
          placeholder: 'Write your post content here...',
        }),
        ImageUpload,
        TweetEmbed,
        Spacer,
      ],
      editorProps: {
        attributes: {
          class: 'ProseMirror',
        },
      },
      onUpdate: () => {
        this.syncToHiddenInput()
      },
      onCreate: ({ editor }) => {
        // Load content after editor is fully initialized
        setTimeout(() => {
          this.loadContent()
        }, 100)
      },
    })

    // Store editor reference
    this.el.__tiptap = this.editor

    console.log("=== TipTapEditor Hook Mount Complete ===")
  },

  createToolbar() {
    const toolbar = this.el.querySelector('.tiptap-toolbar')
    if (!toolbar) return

    toolbar.innerHTML = `
      <button type="button" data-action="bold" title="Bold" class="toolbar-btn"><strong>B</strong></button>
      <button type="button" data-action="italic" title="Italic" class="toolbar-btn"><em>I</em></button>
      <button type="button" data-action="underline" title="Underline" class="toolbar-btn"><u>U</u></button>
      <button type="button" data-action="strike" title="Strike" class="toolbar-btn"><s>S</s></button>
      <span class="separator"></span>
      <button type="button" data-action="heading1" title="Heading 1" class="toolbar-btn">H1</button>
      <button type="button" data-action="heading2" title="Heading 2" class="toolbar-btn">H2</button>
      <button type="button" data-action="heading3" title="Heading 3" class="toolbar-btn">H3</button>
      <span class="separator"></span>
      <button type="button" data-action="bulletList" title="Bullet List" class="toolbar-btn">• List</button>
      <button type="button" data-action="orderedList" title="Numbered List" class="toolbar-btn">1. List</button>
      <button type="button" data-action="blockquote" title="Blockquote" class="toolbar-btn">"</button>
      <span class="separator"></span>
      <button type="button" data-action="link" title="Link" class="toolbar-btn">Link</button>
      <button type="button" data-action="image" title="Image" class="toolbar-btn">Image</button>
      <button type="button" data-action="tweet" title="Tweet" class="toolbar-btn">Tweet</button>
      <button type="button" data-action="spacer" title="Spacer" class="toolbar-btn">---</button>
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
        button.classList.toggle('is-active', isActive)
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
      case 'strike':
        this.editor.chain().focus().toggleStrike().run()
        break
      case 'heading1':
        this.editor.chain().focus().toggleHeading({ level: 1 }).run()
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
      case 'blockquote':
        this.editor.chain().focus().toggleBlockquote().run()
        break
      case 'link':
        this.linkHandler()
        break
      case 'image':
        this.editor.commands.uploadImage()
        break
      case 'tweet':
        this.tweetHandler()
        break
      case 'spacer':
        this.editor.chain().focus().setSpacer().run()
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
      case 'strike':
        return this.editor.isActive('strike')
      case 'heading1':
        return this.editor.isActive('heading', { level: 1 })
      case 'heading2':
        return this.editor.isActive('heading', { level: 2 })
      case 'heading3':
        return this.editor.isActive('heading', { level: 3 })
      case 'bulletList':
        return this.editor.isActive('bulletList')
      case 'orderedList':
        return this.editor.isActive('orderedList')
      case 'blockquote':
        return this.editor.isActive('blockquote')
      case 'link':
        return this.editor.isActive('link')
      default:
        return false
    }
  },

  linkHandler() {
    const url = prompt('Enter URL:')
    if (url) {
      this.editor.chain().focus().setLink({ href: url }).run()
    }
  },

  tweetHandler() {
    const tweetUrl = prompt(
      'Enter Twitter/X post URL:\n(e.g., https://twitter.com/username/status/1234567890)'
    )

    if (!tweetUrl) return

    const tweetPattern = /^https?:\/\/(twitter\.com|x\.com)\/[\w]+\/status\/(\d+)/
    const match = tweetUrl.match(tweetPattern)

    if (!match) {
      alert('Invalid tweet URL. Please use format:\nhttps://twitter.com/username/status/1234567890')
      return
    }

    const tweetId = match[2]
    this.editor.chain().focus().setTweet({ url: tweetUrl, id: tweetId }).run()
  },

  loadContent() {
    const initialContent = this.el.dataset.content
    console.log('=== Loading Content ===')
    console.log('Raw data-content:', initialContent)

    if (initialContent && initialContent !== '{}') {
      try {
        const content = JSON.parse(initialContent)
        console.log('Parsed content:', content)

        // Check if this is Quill format (has "ops" key)
        if (content.ops) {
          console.log('Detected Quill format, converting to plain text for editing')
          // Extract plain text from Quill ops
          let plainText = content.ops.map(op => {
            if (typeof op.insert === 'string') {
              return op.insert
            }
            return ''
          }).join('')

          // Set as plain text in TipTap
          this.editor.commands.setContent(`<p>${plainText.replace(/\n/g, '</p><p>')}</p>`)
          console.log('Converted Quill to plain text')
        } else {
          // This is TipTap format
          this.editor.commands.setContent(content)
          console.log('Content set successfully (TipTap format)')
        }
      } catch (e) {
        console.error('Failed to parse initial content:', e)
      }
    } else {
      console.log('No content to load (empty or missing)')
    }
  },

  syncToHiddenInput() {
    const content = this.editor.getJSON()
    const hiddenInput = this.el.querySelector('input[type="hidden"]')

    if (hiddenInput) {
      hiddenInput.value = JSON.stringify(content)
      hiddenInput.dispatchEvent(new Event('input', { bubbles: true }))
    }
  },

  updated() {
    // Don't reload content on updates - this prevents cursor jumping
    // The editor maintains its own state via the hidden input
  },

  destroyed() {
    if (this.editor) {
      this.editor.destroy()
    }
  },
}

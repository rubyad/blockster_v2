import { Node, mergeAttributes } from '@tiptap/core'

export const TweetEmbed = Node.create({
  name: 'tweet',

  group: 'block',

  atom: true,

  addAttributes() {
    return {
      url: {
        default: null,
      },
      id: {
        default: null,
      },
    }
  },

  parseHTML() {
    return [
      {
        tag: 'div[data-tweet-embed]',
      },
    ]
  },

  renderHTML({ HTMLAttributes }) {
    return [
      'div',
      mergeAttributes(HTMLAttributes, {
        'data-tweet-embed': true,
        'class': 'tweet-embed-placeholder',
        'contenteditable': 'false'
      }),
      ['div', { style: 'padding: 12px; background: #f7f9fa; border: 1px solid #e1e8ed; border-radius: 8px;' },
        ['span', { style: 'color: #657786; font-size: 13px;' }, `Tweet: ${HTMLAttributes.url || ''}`]
      ]
    ]
  },

  addNodeView() {
    return ({ node }) => {
      const dom = document.createElement('div')
      dom.setAttribute('data-tweet-embed', 'true')
      dom.setAttribute('contenteditable', 'false')
      dom.classList.add('tweet-embed-placeholder')
      dom.style.margin = '12px 0'

      const url = node.attrs.url || ''
      const tweetId = node.attrs.id || extractTweetId(url)

      if (!tweetId) {
        dom.innerHTML = `<div style="padding: 12px; background: #f7f9fa; border: 1px solid #e1e8ed; border-radius: 8px;">
          <span style="color: #657786; font-size: 13px;">Invalid tweet URL</span>
        </div>`
        return { dom }
      }

      // Show loading state
      dom.innerHTML = `<div style="padding: 16px; background: #f7f9fa; border: 1px solid #e1e8ed; border-radius: 12px; text-align: center;">
        <div style="display: flex; align-items: center; justify-content: center; gap: 8px; color: #657786; font-size: 13px;">
          <svg style="width: 18px; height: 18px; fill: #1DA1F2;" viewBox="0 0 24 24"><path d="M23.953 4.57a10 10 0 01-2.825.775 4.958 4.958 0 002.163-2.723c-.951.555-2.005.959-3.127 1.184a4.92 4.92 0 00-8.384 4.482C7.69 8.095 4.067 6.13 1.64 3.162a4.822 4.822 0 00-.666 2.475c0 1.71.87 3.213 2.188 4.096a4.904 4.904 0 01-2.228-.616v.06a4.923 4.923 0 003.946 4.827 4.996 4.996 0 01-2.212.085 4.936 4.936 0 004.604 3.417 9.867 9.867 0 01-6.102 2.105c-.39 0-.779-.023-1.17-.067a13.995 13.995 0 007.557 2.209c9.053 0 13.998-7.496 13.998-13.985 0-.21 0-.42-.015-.63A9.935 9.935 0 0024 4.59z"/></svg>
          Loading tweet...
        </div>
      </div>`

      // Load the actual tweet via Twitter widget
      loadTweetWidget(dom, tweetId, url)

      return { dom }
    }
  },

  addCommands() {
    return {
      setTweet: (attributes) => ({ commands }) => {
        return commands.insertContent({
          type: this.name,
          attrs: attributes,
        })
      },
    }
  },
})

function extractTweetId(url) {
  const match = url?.match(/status\/(\d+)/)
  return match ? match[1] : null
}

function loadTweetWidget(container, tweetId, url) {
  // Ensure Twitter widget script is loaded
  if (window.twttr && window.twttr.widgets) {
    renderTweet(container, tweetId, url)
  } else {
    // Load Twitter widget script
    const existingScript = document.querySelector('script[src*="platform.twitter.com/widgets.js"]')
    if (!existingScript) {
      const script = document.createElement('script')
      script.src = 'https://platform.twitter.com/widgets.js'
      script.async = true
      script.onload = () => {
        renderTweet(container, tweetId, url)
      }
      document.head.appendChild(script)
    } else {
      // Script exists but not yet loaded — poll for it
      const poll = setInterval(() => {
        if (window.twttr && window.twttr.widgets) {
          clearInterval(poll)
          renderTweet(container, tweetId, url)
        }
      }, 200)
      // Stop polling after 10s
      setTimeout(() => clearInterval(poll), 10000)
    }
  }
}

function renderTweet(container, tweetId, url) {
  try {
    window.twttr.widgets.createTweet(tweetId, container, {
      theme: 'light',
      dnt: true,
      width: 500,
    }).then((el) => {
      if (!el) {
        // Tweet not found or deleted — show fallback
        showFallback(container, url)
      }
    }).catch(() => {
      showFallback(container, url)
    })
  } catch (e) {
    showFallback(container, url)
  }
}

function showFallback(container, url) {
  container.innerHTML = `<div style="padding: 12px; background: #f7f9fa; border: 1px solid #e1e8ed; border-radius: 8px;">
    <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 4px;">
      <svg style="width: 18px; height: 18px; fill: #1DA1F2;" viewBox="0 0 24 24"><path d="M23.953 4.57a10 10 0 01-2.825.775 4.958 4.958 0 002.163-2.723c-.951.555-2.005.959-3.127 1.184a4.92 4.92 0 00-8.384 4.482C7.69 8.095 4.067 6.13 1.64 3.162a4.822 4.822 0 00-.666 2.475c0 1.71.87 3.213 2.188 4.096a4.904 4.904 0 01-2.228-.616v.06a4.923 4.923 0 003.946 4.827 4.996 4.996 0 01-2.212.085 4.936 4.936 0 004.604 3.417 9.867 9.867 0 01-6.102 2.105c-.39 0-.779-.023-1.17-.067a13.995 13.995 0 007.557 2.209c9.053 0 13.998-7.496 13.998-13.985 0-.21 0-.42-.015-.63A9.935 9.935 0 0024 4.59z"/></svg>
      <span style="font-weight: 600; font-size: 14px; color: #14171a;">Tweet Embed</span>
    </div>
    <a href="${url}" target="_blank" rel="noopener" style="color: #1DA1F2; font-size: 13px; word-break: break-all;">${url}</a>
  </div>`
}

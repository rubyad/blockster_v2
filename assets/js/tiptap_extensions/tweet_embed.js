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
      [
        'div',
        { style: 'padding: 12px; background: #f7f9fa; border: 1px solid #e1e8ed; border-radius: 8px; margin: 12px 0;' },
        [
          'div',
          { style: 'display: flex; align-items: center; gap: 8px; margin-bottom: 8px;' },
          [
            'svg',
            { style: 'width: 20px; height: 20px; fill: #1DA1F2;', viewBox: '0 0 24 24' },
            [
              'path',
              { d: 'M23.953 4.57a10 10 0 01-2.825.775 4.958 4.958 0 002.163-2.723c-.951.555-2.005.959-3.127 1.184a4.92 4.92 0 00-8.384 4.482C7.69 8.095 4.067 6.13 1.64 3.162a4.822 4.822 0 00-.666 2.475c0 1.71.87 3.213 2.188 4.096a4.904 4.904 0 01-2.228-.616v.06a4.923 4.923 0 003.946 4.827 4.996 4.996 0 01-2.212.085 4.936 4.936 0 004.604 3.417 9.867 9.867 0 01-6.102 2.105c-.39 0-.779-.023-1.17-.067a13.995 13.995 0 007.557 2.209c9.053 0 13.998-7.496 13.998-13.985 0-.21 0-.42-.015-.63A9.935 9.935 0 0024 4.59z' }
            ]
          ],
          ['span', { style: 'color: #14171a; font-weight: 600; font-size: 14px;' }, 'Tweet Embed']
        ],
        ['div', { style: 'color: #657786; font-size: 13px; word-break: break-all;' }, HTMLAttributes.url || '']
      ]
    ]
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

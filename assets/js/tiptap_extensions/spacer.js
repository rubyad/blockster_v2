import { Node, mergeAttributes } from '@tiptap/core'

export const Spacer = Node.create({
  name: 'spacer',

  group: 'block',

  atom: true,

  parseHTML() {
    return [
      {
        tag: 'div[data-spacer]',
      },
    ]
  },

  renderHTML({ HTMLAttributes }) {
    return [
      'div',
      mergeAttributes(HTMLAttributes, {
        'data-spacer': true,
        'contenteditable': 'false',
        'style': 'height: 16px; display: block;'
      }),
      [
        'div',
        {
          style: 'height: 16px; background: repeating-linear-gradient(90deg, transparent, transparent 4px, #e0e0e0 4px, #e0e0e0 5px); opacity: 0.3; border-radius: 2px;'
        }
      ]
    ]
  },

  addCommands() {
    return {
      setSpacer: () => ({ commands }) => {
        return commands.insertContent({
          type: this.name,
        })
      },
    }
  },
})

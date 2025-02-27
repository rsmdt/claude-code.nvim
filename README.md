# claude-code.nvim

A minimal Neovim plugin that launches the [Claude Code CLI](https://anthropic.com/claude/code) in a terminal split.

## Features

- Opens a split terminal window running the [Claude CLI](https://anthropic.com/claude/code)
- Configurable window size
- Auto-closes when Claude CLI exits
- Simple and lightweight implementation

## Requirements

- Neovim (0.5.0+)
- [Claude CLI](https://anthropic.com/claude/code) installed and available in your PATH

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'rsmdt/claude-code.nvim',
  keys = {
    { "<leader>cc", "<cmd>ClaudeCode toggle<cr>", desc = "Toggle Claude Code" },
    { "<leader>co", "<cmd>ClaudeCode open<cr>", desc = "Open Claude Code" },
    { "<leader>cx", "<cmd>ClaudeCode close<cr>", desc = "Close Claude Code" },
  },
}
```

## Setup

In your Neovim configuration:

```lua
require("claude-code").setup({
  -- Optional configuration
  window = {
    width = 0.8,     -- 80% of editor width
    height = 0.8,    -- 80% of editor height
  },
  command = "claude", -- Command to run (change if claude is installed elsewhere)
  mappings = {
    close = "<leader><Esc>",  -- Key to exit and close the window (leader key + Escape)
  },
})
```

## Usage

The plugin provides several commands:

- `:ClaudeCode` or `:ClaudeCode toggle` - Toggle the Claude CLI terminal (open if closed, close if open)
- `:ClaudeCode open` - Open a new Claude CLI terminal
- `:ClaudeCode close` - Close any open Claude CLI terminal

You can map these commands to keys in your Neovim configuration:

```lua
-- Example keymaps
vim.keymap.set('n', '<leader>cc', ':ClaudeCode toggle<CR>', { silent = true })
vim.keymap.set('n', '<leader>co', ':ClaudeCode open<CR>', { silent = true })
vim.keymap.set('n', '<leader>cx', ':ClaudeCode close<CR>', { silent = true })
```

### Controls

- Press `<leader><Esc>` to exit terminal mode and close the Claude Code window
- Use `Ctrl+h`, `Ctrl+j`, `Ctrl+k`, `Ctrl+l` to navigate between windows while in terminal mode
- The window will automatically close when the Claude CLI process exits
- While in the [Claude CLI](https://anthropic.com/claude/code), use its native commands and functionality
- You can customize the exit key by changing the `mappings.close` option
- Note: By default, the leader key is typically `\` unless you've customized it

## Todo

- Add support for custom Claude CLI flags
- Save conversation history to files
- Add ability to load previous conversations

## License

[MIT License](LICENSE)
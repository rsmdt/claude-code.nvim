if vim.g.loaded_claude_code then
  return
end
vim.g.loaded_claude_code = true

-- Define the :ClaudeCode command
vim.api.nvim_create_user_command("ClaudeCode", function()
  require("claude-code").open()
end, {})
if vim.g.loaded_claude_code then
  return
end
vim.g.loaded_claude_code = true

-- Define the :ClaudeCode command with subcommands
vim.api.nvim_create_user_command("ClaudeCode", function(opts)
  local claude_code = require("claude-code")
  local cmd = opts.args
  
  if cmd == "" or cmd == "toggle" then
    claude_code.toggle()
  elseif cmd == "open" then
    claude_code.open()
  elseif cmd == "close" then
    claude_code.close()
  elseif cmd == "terminal" then
    claude_code.open_terminal()
  elseif cmd == "sidebar" then
    claude_code.open_sidebar()
  else
    vim.notify("Invalid command: " .. cmd .. ". Use 'toggle', 'open', 'close', 'terminal', or 'sidebar'.", vim.log.levels.ERROR)
  end
end, {
  nargs = "?",
  complete = function()
    return { "toggle", "open", "close", "terminal", "sidebar" }
  end
})
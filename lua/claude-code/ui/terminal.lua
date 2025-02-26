local M = {}
local config = require("claude-code.core.config")

-- Open Claude CLI in terminal mode
function M.open()
  local cfg = config.get()
  -- Calculate window size
  local width = math.floor(vim.o.columns * cfg.window.width)
  local height = math.floor(vim.o.lines * cfg.window.height)
  
  -- Create a new buffer for the terminal
  local bufnr = vim.api.nvim_create_buf(false, true)
  
  -- Mark this as a claude-code buffer
  vim.api.nvim_buf_set_var(bufnr, "claude_code_terminal", true)
  vim.api.nvim_buf_set_name(bufnr, "Claude Code")
  
  -- Create split and show the buffer
  vim.cmd("botright split")
  vim.cmd("resize " .. height)
  vim.api.nvim_set_current_buf(bufnr)
  
  -- Set buffer options
  vim.bo.bufhidden = "wipe"
  
  -- Start terminal with Claude CLI
  local job_id = vim.fn.termopen(cfg.command, {
    -- Auto-close terminal window when process exits
    on_exit = function(job_id, exit_code, event_type)
      -- Use vim.schedule to avoid "E565: Not allowed to change text or change window"
      vim.schedule(function()
        -- Safety check - we'll use pcall to prevent any errors from being thrown
        pcall(function()
          -- Get the window ID for this buffer
          local win_id = vim.fn.bufwinid(bufnr)
          -- Only try to close the window if it exists
          if win_id ~= -1 then
            pcall(vim.api.nvim_win_close, win_id, true)
          end
          
          -- Only try to delete the buffer if it's valid
          if vim.api.nvim_buf_is_valid(bufnr) then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
          end
        end)
      end)
    end
  })
  
  -- Set up terminal mode mappings for this buffer
  -- Map leader+Escape to terminate process and close window
  vim.api.nvim_buf_set_keymap(
    bufnr, 
    "t", 
    cfg.mappings.close, 
    "<C-\\><C-n>:lua require('claude-code').close()<CR>", 
    { noremap = true, silent = true }
  )
  
  -- Add window navigation keymaps for Ctrl+h,j,k,l in terminal mode
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "t",
    "<C-h>",
    "<C-\\><C-n><C-w>h",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "t",
    "<C-j>",
    "<C-\\><C-n><C-w>j",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "t",
    "<C-k>",
    "<C-\\><C-n><C-w>k",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "t",
    "<C-l>",
    "<C-\\><C-n><C-w>l",
    { noremap = true, silent = true }
  )
  
  -- Enter terminal mode automatically
  vim.cmd("startinsert")
  
  return bufnr
end

return M
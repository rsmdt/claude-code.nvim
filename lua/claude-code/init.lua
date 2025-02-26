local M = {}

-- Configuration with defaults
M.config = {
  mode = "terminal",   -- Mode to use: "terminal" (more modes to be added)
  window = {
    width = 0.8,       -- 80% of editor width
    height = 0.8,      -- 80% of editor height
  },
  command = "claude",  -- Assumes claude cli is in path
  mappings = {
    close = "<leader><Esc>",  -- Key to exit and close the window
  },
}

-- Setup function
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Check if Claude Code terminal is currently open
function M.is_open()
  -- Check all buffers for claude_code_terminal flag
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local is_claude_buffer = pcall(function() 
      return vim.api.nvim_buf_get_var(bufnr, "claude_code_terminal") 
    end)
    
    if is_claude_buffer and vim.api.nvim_buf_is_valid(bufnr) then
      -- Check if buffer has a window (is visible)
      if vim.fn.bufwinid(bufnr) ~= -1 then
        return true, bufnr
      end
    end
  end
  
  return false, nil
end

-- Function to close the Claude Code terminal
function M.close()
  -- First check if the current buffer is a Claude Code buffer
  local bufnr = vim.api.nvim_get_current_buf()
  local is_claude_buffer = pcall(function() 
    return vim.api.nvim_buf_get_var(bufnr, "claude_code_terminal") 
  end)
  
  -- If current buffer is not a Claude Code buffer, try to find one
  if not is_claude_buffer then
    local is_open, found_bufnr = M.is_open()
    if is_open then
      bufnr = found_bufnr
    else
      -- No Claude Code terminal is open
      return
    end
  end
  
  -- Get window ID for buffer
  local win_id = vim.fn.bufwinid(bufnr)
  
  -- Stop any running job in this buffer (send SIGTERM)
  pcall(function()
    local job_id = vim.b[bufnr].terminal_job_id
    if job_id then
      vim.fn.jobstop(job_id)
    end
  end)
  
  -- Wait a brief moment to allow the job to terminate
  vim.cmd("sleep 100m")
  
  -- Close the window if it exists
  if win_id ~= -1 then
    pcall(vim.api.nvim_win_close, win_id, true)
  end
  
  -- Delete the buffer forcefully
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
end


-- Open Claude CLI based on configured mode
function M.open()
  if M.config.mode == "terminal" then
    M.open_terminal()
  else
    vim.notify("Unsupported mode: " .. M.config.mode, vim.log.levels.ERROR)
  end
end

-- Open Claude CLI in terminal mode
function M.open_terminal()
  -- Calculate window size
  local width = math.floor(vim.o.columns * M.config.window.width)
  local height = math.floor(vim.o.lines * M.config.window.height)
  
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
  local job_id = vim.fn.termopen(M.config.command, {
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
    M.config.mappings.close, 
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
end

-- Toggle Claude Code terminal
function M.toggle()
  local is_open = M.is_open()
  if is_open then
    M.close()
  else
    M.open()
  end
end

return M


local M = {}

-- Configuration with defaults
M.config = {
  window = {
    width = 0.8,     -- 80% of editor width
    height = 0.8,    -- 80% of editor height
  },
  command = "claude", -- Assumes claude cli is in path
  mappings = {
    close = "<leader><Esc>",  -- Key to exit and close the window
  },
}

-- Setup function
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Function to forcibly close the terminal window and kill the process
function M.force_close()
  -- Get current buffer
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Check if this is a claude-code buffer
  local is_claude_buffer = pcall(function() 
    return vim.api.nvim_buf_get_var(bufnr, "claude_code_terminal") 
  end)
  
  if is_claude_buffer then
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
end

-- Open Claude CLI in terminal
function M.open()
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
  -- Map leader+Escape to forcibly terminate process and close window
  vim.api.nvim_buf_set_keymap(
    bufnr, 
    "t", 
    M.config.mappings.close, 
    "<C-\\><C-n>:lua require('claude-code').force_close()<CR>", 
    { noremap = true, silent = true }
  )
  
  -- Enter terminal mode automatically
  vim.cmd("startinsert")
end

return M


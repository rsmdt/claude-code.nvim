local M = {}

-- Import modules
local config = require("claude-code.core.config")
local utils = require("claude-code.utils")
local terminal = require("claude-code.ui.terminal")
local sidebar = require("claude-code.ui.sidebar")

-- Public: Setup function for user configuration
function M.setup(opts)
  config.setup(opts)
end

-- Check if Claude Code interface is currently open
function M.is_open()
  -- Check all buffers for claude_code flag
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    -- Check for claude_code_terminal flag (terminal mode)
    local is_claude_terminal = pcall(function() 
      return vim.api.nvim_buf_get_var(bufnr, "claude_code_terminal") 
    end)
    
    -- Check for claude_code_sidebar flag (sidebar mode)
    local is_claude_sidebar = pcall(function() 
      return vim.api.nvim_buf_get_var(bufnr, "claude_code_sidebar_output") 
    end)
    
    if (is_claude_terminal or is_claude_sidebar) and vim.api.nvim_buf_is_valid(bufnr) then
      -- Check if buffer has a window (is visible)
      if vim.fn.bufwinid(bufnr) ~= -1 then
        return true, bufnr
      end
    end
  end
  
  return false, nil
end

-- Function to close any Claude Code interface
function M.close()
  -- Check for terminal mode buffer
  local terminal_bufnr = nil
  local is_terminal = false
  
  -- Check for sidebar mode buffers
  local input_bufnr = nil
  local output_bufnr = nil
  local is_sidebar = false
  
  -- Check if any of the currently visible buffers are Claude Code buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      -- Check for terminal buffer
      local is_terminal_buffer = pcall(function() 
        return vim.api.nvim_buf_get_var(bufnr, "claude_code_terminal") 
      end)
      
      if is_terminal_buffer then
        terminal_bufnr = bufnr
        is_terminal = true
      end
      
      -- Check for sidebar input buffer
      local is_input_buffer = pcall(function() 
        return vim.api.nvim_buf_get_var(bufnr, "claude_code_sidebar_input") 
      end)
      
      if is_input_buffer then
        input_bufnr = bufnr
        is_sidebar = true
      end
      
      -- Check for sidebar output buffer
      local is_output_buffer = pcall(function() 
        return vim.api.nvim_buf_get_var(bufnr, "claude_code_sidebar_output") 
      end)
      
      if is_output_buffer then
        output_bufnr = bufnr
        is_sidebar = true
      end
    end
  end
  
  -- Close terminal mode if open
  if is_terminal and terminal_bufnr then
    -- Get window ID for buffer
    local win_id = vim.fn.bufwinid(terminal_bufnr)
    
    -- Stop any running job in this buffer (send SIGTERM)
    pcall(function()
      local job_id = vim.b[terminal_bufnr].terminal_job_id
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
    if vim.api.nvim_buf_is_valid(terminal_bufnr) then
      pcall(vim.api.nvim_buf_delete, terminal_bufnr, { force = true })
    end
  end
  
  -- Close sidebar mode if open
  if is_sidebar then
    -- Close and delete input buffer
    if input_bufnr and vim.api.nvim_buf_is_valid(input_bufnr) then
      local input_win_id = vim.fn.bufwinid(input_bufnr)
      if input_win_id ~= -1 then
        pcall(vim.api.nvim_win_close, input_win_id, true)
      end
      pcall(vim.api.nvim_buf_delete, input_bufnr, { force = true })
    end
    
    -- Close and delete output buffer
    if output_bufnr and vim.api.nvim_buf_is_valid(output_bufnr) then
      local output_win_id = vim.fn.bufwinid(output_bufnr)
      if output_win_id ~= -1 then
        pcall(vim.api.nvim_win_close, output_win_id, true)
      end
      pcall(vim.api.nvim_buf_delete, output_bufnr, { force = true })
    end
    
    -- Stop any running job associated with the sidebar
    pcall(function()
      if sidebar.state.sidebar_job_id then
        vim.fn.jobstop(sidebar.state.sidebar_job_id)
        sidebar.state.sidebar_job_id = nil
      end
    end)
  end
end

-- Open Claude based on configured mode
function M.open()
  local cfg = config.get()
  
  if cfg.mode == "terminal" then
    -- For terminal mode, we need Claude CLI
    if not utils.is_claude_available() then
      vim.notify("Claude CLI not found in PATH. Please make sure '" .. cfg.command .. "' is installed and available.", vim.log.levels.ERROR)
      return
    end
    terminal.open()
  elseif cfg.mode == "sidebar" then
    -- For sidebar mode, we use MCP and need curl
    if not utils.is_curl_available() then
      vim.notify("Curl not found in PATH. Please make sure 'curl' is installed for API access.", vim.log.levels.ERROR)
      return
    end
    
    -- Initialize the sidebar and store handlers
    local handlers = sidebar.open()
    -- Save the submit function in the sidebar module for the public API
    sidebar.submit_query_func = handlers.submit_query
  else
    vim.notify("Unsupported mode: " .. cfg.mode, vim.log.levels.ERROR)
  end
end

-- Toggle Claude Code interface
function M.toggle()
  local is_open = M.is_open()
  if is_open then
    M.close()
  else
    M.open()
  end
end

-- Public: Submit a query to the sidebar
function M.submit_sidebar_query()
  sidebar.submit_sidebar_query()
end

-- Public: Interrupt a running query in the sidebar
function M.interrupt_sidebar_query()
  sidebar.interrupt_sidebar_query()
end

return M
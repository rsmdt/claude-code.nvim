local M = {}

-- Configuration with defaults
M.config = {
  mode = "terminal",   -- Mode to use: "terminal" or "sidebar"
  window = {
    width = 0.8,       -- 80% of editor width (terminal mode)
    height = 0.8,      -- 80% of editor height (terminal mode)
    sidebar = {
      width = 0.3,     -- 30% of editor width
      input_height = 5, -- Number of lines for input field
      float = true,    -- Whether to use a floating window (true) or split (false)
      border = "rounded" -- Border style: "none", "single", "double", "rounded", "solid", or "shadow"
    }
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
  -- Check all buffers for claude_code flag
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    -- Check for claude_code_terminal flag (terminal mode)
    local is_claude_terminal = pcall(function() 
      return vim.api.nvim_buf_get_var(bufnr, "claude_code_terminal") 
    end)
    
    -- Check for claude_code_sidebar flag (sidebar mode)
    local is_claude_sidebar = pcall(function() 
      return vim.api.nvim_buf_get_var(bufnr, "claude_code_sidebar") 
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
      if M.sidebar_job_id then
        vim.fn.jobstop(M.sidebar_job_id)
        M.sidebar_job_id = nil
      end
    end)
  end
end


-- Open Claude CLI based on configured mode
function M.open()
  if M.config.mode == "terminal" then
    M.open_terminal()
  elseif M.config.mode == "sidebar" then
    M.open_sidebar()
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

-- Open Claude CLI in sidebar mode with input and output buffers
function M.open_sidebar()
  -- Store original window to return to later
  local original_win = vim.api.nvim_get_current_win()
  
  -- Calculate floating window dimensions and position
  local total_width = math.floor(vim.o.columns * M.config.window.sidebar.width)
  local total_height = math.floor(vim.o.lines * 0.8) -- 80% of editor height
  local input_height = M.config.window.sidebar.input_height
  local output_height = total_height - input_height - 1 -- -1 for the border
  
  -- Position the window in the center-right of the screen
  local col = math.floor(vim.o.columns - total_width - 2) -- -2 for some padding
  local row = math.floor((vim.o.lines - total_height) / 2)
  
  -- Create output buffer (for Claude responses)
  local output_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_var(output_bufnr, "claude_code_sidebar_output", true)
  vim.api.nvim_buf_set_name(output_bufnr, "Claude Output")
  
  -- Set output buffer options (including readonly)
  vim.api.nvim_buf_set_option(output_bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(output_bufnr, "swapfile", false)
  vim.api.nvim_buf_set_option(output_bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(output_bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(output_bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(output_bufnr, "readonly", true)
  
  -- Create floating window for output (top part)
  local output_win_config = {
    relative = "editor",
    width = total_width,
    height = output_height,
    col = col,
    row = row,
    style = "minimal",
    border = M.config.window.sidebar.border,
    title = " Claude Output ",
    title_pos = "center"
  }
  
  local output_win = vim.api.nvim_open_win(output_bufnr, false, output_win_config)
  
  -- Set window options for output window
  vim.api.nvim_win_set_option(output_win, "wrap", true)
  vim.api.nvim_win_set_option(output_win, "linebreak", true)
  vim.api.nvim_win_set_option(output_win, "foldmethod", "manual")
  vim.api.nvim_win_set_option(output_win, "foldenable", false)
  vim.api.nvim_win_set_option(output_win, "winhl", "Normal:NormalFloat,FloatBorder:FloatBorder")
  vim.api.nvim_win_set_option(output_win, "winhighlight", "NormalFloat:Normal,FloatBorder:Special")
  
  -- Create input buffer
  local input_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_var(input_bufnr, "claude_code_sidebar_input", true)
  vim.api.nvim_buf_set_name(input_bufnr, "Claude Input")
  
  -- Create floating window for input (bottom part)
  local input_win_config = {
    relative = "editor",
    width = total_width,
    height = input_height,
    col = col,
    row = row + output_height + 1, -- +1 for the border
    style = "minimal",
    border = M.config.window.sidebar.border,
    title = " Prompt (Ctrl+Enter to submit) ",
    title_pos = "center"
  }
  
  local input_win = vim.api.nvim_open_win(input_bufnr, true, input_win_config)
  
  -- Set buffer options for input
  vim.api.nvim_buf_set_option(input_bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(input_bufnr, "swapfile", false)
  vim.api.nvim_buf_set_option(input_bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(input_bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(input_bufnr, "modifiable", true)
  
  -- Set window options for input window
  vim.api.nvim_win_set_option(input_win, "wrap", true)
  vim.api.nvim_win_set_option(input_win, "linebreak", true)
  vim.api.nvim_win_set_option(input_win, "winhl", "Normal:NormalFloat,FloatBorder:FloatBorder")
  vim.api.nvim_win_set_option(input_win, "winhighlight", "NormalFloat:Normal,FloatBorder:Special")
  
  -- Set initial output content (needs to temporarily make it modifiable)
  vim.api.nvim_buf_set_option(output_bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(output_bufnr, 0, -1, false, {
    "Claude CLI - Sidebar Mode",
    "",
    "Type your queries in the input box below and press Ctrl+Enter to submit.",
    "Claude's responses will appear here just like in the terminal.",
    "",
    "Use Ctrl+h/j/k/l to navigate between windows.",
    "Press " .. M.config.mappings.close .. " to close the sidebar.",
    "",
    "---"
  })
  vim.api.nvim_buf_set_option(output_bufnr, "modifiable", false)
  
  -- Function to handle submit action
  local function submit_query()
    -- Get input text
    local input_text = table.concat(vim.api.nvim_buf_get_lines(input_bufnr, 0, -1, false), "\n")
    
    if input_text:gsub("%s+", "") == "" then
      return -- Don't submit empty queries
    end
    
    -- Make output buffer modifiable temporarily
    vim.api.nvim_buf_set_option(output_bufnr, "modifiable", true)
    
    -- Append user query to output buffer in a format similar to Claude CLI
    local current_lines = vim.api.nvim_buf_line_count(output_bufnr)
    vim.api.nvim_buf_set_lines(output_bufnr, current_lines, current_lines, false, {
      "Human: " .. input_text:gsub("\n", "\nHuman: "),
      "",
      "Assistant: Thinking..."
    })
    
    -- Make output buffer readonly again
    vim.api.nvim_buf_set_option(output_bufnr, "modifiable", false)
    
    -- Clear input buffer
    vim.api.nvim_buf_set_lines(input_bufnr, 0, -1, false, {""})
    
    -- Scroll output to bottom
    vim.api.nvim_win_set_cursor(output_win, {vim.api.nvim_buf_line_count(output_bufnr), 0})
    
    -- We'll use a shell script to pipe the input to Claude CLI
    -- This gives us more control over the process and ensures we get real-time output
    local temp_script = os.tmpname() .. ".sh"
    local temp_input = os.tmpname()
    
    -- Write input to temp file
    local input_file = io.open(temp_input, "w")
    input_file:write(input_text)
    input_file:close()
    
    -- Create shell script that will run Claude and handle output properly
    local script_file = io.open(temp_script, "w")
    script_file:write([[
#!/bin/sh
# Pipe input to Claude CLI and ensure output is line-buffered for streaming
cat "]] .. temp_input .. [[" | ]] .. M.config.command .. [[ | stdbuf -oL cat
rm -f "]] .. temp_input .. [[" # Clean up input file
]])
    script_file:close()
    
    -- Make script executable
    os.execute("chmod +x " .. temp_script)
    
    -- Command to run our script
    local cmd = temp_script
    
    -- Variables to track response state
    local response_started = false
    local response_line = current_lines + 2 -- Line with "Assistant: Thinking..."
    
    -- Start job to run Claude CLI
    M.sidebar_job_id = vim.fn.jobstart(cmd, {
      stdout_buffered = false, -- Disable buffering for real-time streaming
      on_stdout = function(_, data, _)
        if data and #data > 0 then
          -- Skip any empty lines at the beginning
          local content = {}
          for _, line in ipairs(data) do
            if line ~= "" or #content > 0 then
              table.insert(content, line)
            end
          end
          
          if #content > 0 then
            -- Make output buffer modifiable temporarily
            vim.api.nvim_buf_set_option(output_bufnr, "modifiable", true)
            
            -- If this is the first response chunk, replace "Thinking..." with the response
            if not response_started then
              response_started = true
              
              -- Get the "Assistant: Thinking..." line
              local thinking_line = vim.api.nvim_buf_get_lines(output_bufnr, response_line, response_line + 1, false)[1]
              
              if thinking_line and thinking_line:match("Assistant: Thinking%.%.%.") then
                -- Replace "Assistant: Thinking..." with "Assistant: " + first part of response
                local first_line = "Assistant: " .. content[1]
                vim.api.nvim_buf_set_lines(output_bufnr, response_line, response_line + 1, false, {first_line})
                
                -- Add the rest of the content if any
                if #content > 1 then
                  -- For each subsequent line, we need to append to the buffer
                  for i = 2, #content do
                    local last_line = vim.api.nvim_buf_line_count(output_bufnr)
                    vim.api.nvim_buf_set_lines(output_bufnr, last_line, last_line, false, {content[i]})
                  end
                end
              else
                -- Something went wrong, just append content at the end
                for _, line in ipairs(content) do
                  local last_line = vim.api.nvim_buf_line_count(output_bufnr)
                  vim.api.nvim_buf_set_lines(output_bufnr, last_line, last_line, false, {line})
                end
              end
            else
              -- For subsequent response chunks, append to the response
              for _, line in ipairs(content) do
                local last_line = vim.api.nvim_buf_line_count(output_bufnr)
                vim.api.nvim_buf_set_lines(output_bufnr, last_line, last_line, false, {line})
              end
            end
            
            -- Make output buffer readonly again
            vim.api.nvim_buf_set_option(output_bufnr, "modifiable", false)
            
            -- Scroll output to bottom
            vim.api.nvim_win_set_cursor(output_win, {vim.api.nvim_buf_line_count(output_bufnr), 0})
          end
        end
      end,
      on_exit = function()
        -- Make output buffer modifiable temporarily
        vim.api.nvim_buf_set_option(output_bufnr, "modifiable", true)
        
        -- Add separator after response
        vim.api.nvim_buf_set_lines(output_bufnr, -1, -1, false, {"", "---", ""})
        
        -- Make output buffer readonly again
        vim.api.nvim_buf_set_option(output_bufnr, "modifiable", false)
        
        -- Clean up temp files
        pcall(os.remove, temp_script)
        pcall(os.remove, temp_input)
        
        -- Scroll output to bottom
        vim.api.nvim_win_set_cursor(output_win, {vim.api.nvim_buf_line_count(output_bufnr), 0})
        
        -- Focus input window again and enter insert mode
        vim.api.nvim_set_current_win(input_win)
        vim.cmd("startinsert")
      end
    })
  end
  
  -- Set up keymaps for input buffer
  -- Map Ctrl+Enter to submit query
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "i",
    "<C-CR>",
    "<Esc>:lua require('claude-code').submit_sidebar_query()<CR>a",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "n",
    "<C-CR>",
    ":lua require('claude-code').submit_sidebar_query()<CR>",
    { noremap = true, silent = true }
  )
  
  -- Map close key
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "n",
    M.config.mappings.close,
    ":lua require('claude-code').close()<CR>",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    output_bufnr,
    "n",
    M.config.mappings.close,
    ":lua require('claude-code').close()<CR>",
    { noremap = true, silent = true }
  )
  
  -- Add window navigation keymaps
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "n",
    "<C-h>",
    "<C-w>h",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "n",
    "<C-j>",
    "<C-w>j",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "n",
    "<C-k>",
    "<C-w>k",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "n",
    "<C-l>",
    "<C-w>l",
    { noremap = true, silent = true }
  )
  
  -- Focus input window and start in insert mode right away
  vim.api.nvim_set_current_win(input_win)
  vim.cmd("startinsert")
  
  -- Expose submit function globally
  M.submit_sidebar_query = submit_query
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


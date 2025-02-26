local M = {}
local config = require("claude-code.core.config")
local mcp = require("claude-code.api.mcp")
local editor = require("claude-code.core.editor")

-- Sidebar module state
M.state = {
  output_bufnr = nil,
  output_win = nil,
  input_bufnr = nil,
  input_win = nil,
  thinking_timer = nil,
  sidebar_job_id = nil,
  current_query = nil,
  buffer_contents = nil,
}

-- Open Claude sidebar with input and output buffers using MCP API
function M.open()
  local cfg = config.get()
  
  -- Store original window to return to later
  local original_win = vim.api.nvim_get_current_win()
  
  -- Calculate floating window dimensions and position
  local total_width = math.floor(vim.o.columns * cfg.window.sidebar.width)
  local total_height = math.floor(vim.o.lines * 0.8) -- 80% of editor height
  local input_height = cfg.window.sidebar.input_height
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
    border = cfg.window.sidebar.border,
    title = " Claude Output ",
    title_pos = "center"
  }
  
  local output_win = vim.api.nvim_open_win(output_bufnr, false, output_win_config)
  
  -- Set window options for output window
  local should_wrap = cfg.window.sidebar.output == "wrap"
  vim.api.nvim_win_set_option(output_win, "wrap", should_wrap)
  vim.api.nvim_win_set_option(output_win, "linebreak", should_wrap)
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
    border = cfg.window.sidebar.border,
    title = " Prompt (Enter to submit, Shift+Enter for new line) ",
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
  
  -- Set output buffer as modifiable for initialization
  vim.api.nvim_buf_set_option(output_bufnr, "modifiable", true)
  
  -- Display a welcome message
  vim.api.nvim_buf_set_lines(output_bufnr, 0, -1, false, {
    "Claude API initialized successfully!",
    "Using model: " .. cfg.mcp.model,
    "",
    "---",
    "",
    "Type your queries in the input box below and press Enter to submit.",
    "Press Shift+Enter to add a new line in the input.",
    "Press Esc to interrupt a running query.",
    "Use Ctrl+h/j/k/l to navigate between windows.",
    "Press " .. cfg.mappings.close .. " to close the sidebar.",
    "",
    "---",
    ""
  })
  
  -- Make output buffer readonly again
  vim.api.nvim_buf_set_option(output_bufnr, "modifiable", false)
  
  -- Focus input window again and ensure it's editable and in insert mode
  vim.api.nvim_set_current_win(input_win)
  vim.api.nvim_buf_set_option(input_bufnr, "modifiable", true)
  vim.cmd("startinsert")
  
  -- Function to handle submit action with MCP
  local function submit_query()
    -- Check if a query is already in progress
    if M.state.sidebar_job_id and vim.fn.jobwait({M.state.sidebar_job_id}, 0)[1] == -1 then
      vim.notify("A query is already in progress. Please wait or press Esc to interrupt.", vim.log.levels.INFO)
      return
    end
    
    -- Get input text
    local input_text = table.concat(vim.api.nvim_buf_get_lines(input_bufnr, 0, -1, false), "\n")
    
    if input_text:gsub("%s+", "") == "" then
      return -- Don't submit empty queries
    end
    
    -- Make output buffer modifiable temporarily
    vim.api.nvim_buf_set_option(output_bufnr, "modifiable", true)
    
    -- Append user query to output buffer in a chat format
    local current_lines = vim.api.nvim_buf_line_count(output_bufnr)
    vim.api.nvim_buf_set_lines(output_bufnr, current_lines, current_lines, false, {
      "Human: " .. input_text:gsub("\n", "\nHuman: "),
      "",
      "Assistant: Thinking"
    })
    
    -- Start thinking animation and elapsed time tracking
    local thinking_line = current_lines + 2 -- Line with "Assistant: Thinking"
    local dots = 0
    local start_time = os.time()
    local thinking_timer = vim.loop.new_timer()
    
    -- Keep track of timer so we can stop it when needed
    M.state.thinking_timer = thinking_timer
    
    -- Update thinking dots and elapsed time every 500ms
    thinking_timer:start(0, 500, vim.schedule_wrap(function()
      -- Calculate elapsed time
      local elapsed_seconds = os.difftime(os.time(), start_time)
      local mins = math.floor(elapsed_seconds / 60)
      local secs = math.floor(elapsed_seconds % 60)
      local elapsed_str = string.format("%02d:%02d", mins, secs)
      
      -- Update dots (cycle between 1 and 3 dots)
      dots = (dots % 3) + 1
      local dot_str = string.rep(".", dots)
      
      -- Make the buffer modifiable
      pcall(vim.api.nvim_buf_set_option, output_bufnr, "modifiable", true)
      
      -- Update the thinking line with dots and elapsed time
      pcall(vim.api.nvim_buf_set_lines, output_bufnr, thinking_line, thinking_line + 1, false, 
        {"Assistant: Thinking" .. dot_str .. " [" .. elapsed_str .. "] (Press Esc to interrupt)"})
      
      -- Make the buffer readonly again
      pcall(vim.api.nvim_buf_set_option, output_bufnr, "modifiable", false)
    end))
    
    -- Make output buffer readonly again
    vim.api.nvim_buf_set_option(output_bufnr, "modifiable", false)
    
    -- Clear input buffer
    vim.api.nvim_buf_set_lines(input_bufnr, 0, -1, false, {""})
    
    -- Make sure input buffer is modifiable
    pcall(vim.api.nvim_buf_set_option, input_bufnr, "modifiable", true)
    
    -- Scroll output to bottom
    vim.api.nvim_win_set_cursor(output_win, {vim.api.nvim_buf_line_count(output_bufnr), 0})
    
    -- Variables to track response state
    local response_started = false
    local response_line = thinking_line -- Line with "Assistant: Thinking..."
    
    -- Store current query information for interruption
    local current_query = {
      timer = thinking_timer,
      response_line = response_line,
      thinking_line = thinking_line,
      interrupted = false
    }
    M.state.current_query = current_query
    
    -- Define callback function for request completion
    local function handle_complete(full_response)
      -- Use vim.schedule to ensure UI operations happen in the main thread
      vim.schedule(function()
        -- Stop thinking animation if it's still running
        if thinking_timer and thinking_timer:is_active() then
          thinking_timer:stop()
          thinking_timer:close()
        end
        
        -- Make output buffer modifiable temporarily
        pcall(vim.api.nvim_buf_set_option, output_bufnr, "modifiable", true)
        
        -- Add separator after response
        pcall(vim.api.nvim_buf_set_lines, output_bufnr, -1, -1, false, {"", "---", ""})
        
        -- Check if there are any code edits to apply
        local edits_result = editor.apply_code_edits(full_response)
        
        -- If changes were made, show a notification
        if edits_result.success and edits_result.changes_made then
          -- Add summary of changes to the output buffer
          pcall(vim.api.nvim_buf_set_lines, output_bufnr, -1, -1, false, {
            "",
            "🔧 Applied code changes:",
            ""
          })
          
          -- List all the changes
          for _, result in ipairs(edits_result.results) do
            local status = result.success and "✅" or "❌"
            pcall(vim.api.nvim_buf_set_lines, output_bufnr, -1, -1, false, {
              status .. " " .. result.file .. ": " .. result.message
            })
          end
          
          pcall(vim.api.nvim_buf_set_lines, output_bufnr, -1, -1, false, {""})
          
          -- Notify user about the changes
          local success_count = 0
          for _, result in ipairs(edits_result.results) do
            if result.success then
              success_count = success_count + 1
            end
          end
          
          vim.notify("Applied " .. success_count .. " code changes", vim.log.levels.INFO)
        elseif edits_result.success and not edits_result.changes_made then
          -- No changes were made, but blocks were detected
          vim.notify("No code changes applied - check the output for details", vim.log.levels.WARN)
        end
        
        -- Make output buffer readonly again
        pcall(vim.api.nvim_buf_set_option, output_bufnr, "modifiable", false)
        
        -- Scroll output to bottom
        pcall(vim.api.nvim_win_set_cursor, output_win, {vim.api.nvim_buf_line_count(output_bufnr), 0})
        
        -- Make sure input buffer is modifiable
        pcall(vim.api.nvim_buf_set_option, input_bufnr, "modifiable", true)
        
        -- Focus input window again and enter insert mode
        pcall(vim.api.nvim_set_current_win, input_win)
        vim.cmd("startinsert")
        
        -- Clear current query reference
        M.state.current_query = nil
        M.state.sidebar_job_id = nil
      end)
    end
    
    -- Define on_chunk callback function for mcp_request
    local function handle_chunk(content)
      -- Process the response in a scheduled callback to avoid UI issues
      vim.schedule(function()
        -- Stop the thinking animation when we start getting real output
        if thinking_timer and thinking_timer:is_active() then
          thinking_timer:stop()
          thinking_timer:close()
        end
        
        if content and #content > 0 then
          -- Make output buffer modifiable temporarily
          pcall(vim.api.nvim_buf_set_option, output_bufnr, "modifiable", true)
          
          -- If this is the first response chunk, replace "Thinking..." with the response
          if not response_started then
            response_started = true
            
            -- Find the "Assistant: Thinking" line (may have dots and elapsed time)
            local found = false
            for i = 0, 5 do -- Check a few lines around expected position
              local check_line = response_line + i
              if check_line < vim.api.nvim_buf_line_count(output_bufnr) then
                local line_text = vim.api.nvim_buf_get_lines(output_bufnr, check_line, check_line + 1, false)[1]
                if line_text and line_text:match("^Assistant: Thinking") then
                  -- Replace thinking line with first line of response
                  pcall(vim.api.nvim_buf_set_lines, output_bufnr, check_line, check_line + 1, false, {"Assistant: " .. content})
                  response_line = check_line
                  found = true
                  break
                end
              end
            end
            
            if not found then
              -- Fallback: just append content at the end
              local last_line = vim.api.nvim_buf_line_count(output_bufnr)
              pcall(vim.api.nvim_buf_set_lines, output_bufnr, last_line, last_line, false, {"Assistant: " .. content})
            end
          else
            -- For subsequent chunks, append to the last line or add new lines
            local lines = vim.api.nvim_buf_get_lines(output_bufnr, 0, -1, false)
            local last_line_idx = #lines
            local last_line = lines[last_line_idx]
            
            -- Process the chunk to handle newlines
            local parts = {}
            local start_idx = 1
            local curr_idx = 1
            
            -- Split the chunk at newlines
            while curr_idx <= #content do
              if content:sub(curr_idx, curr_idx) == "\n" then
                table.insert(parts, content:sub(start_idx, curr_idx - 1))
                start_idx = curr_idx + 1
              end
              curr_idx = curr_idx + 1
            end
            
            -- Add the last part if there is one
            if start_idx <= #content then
              table.insert(parts, content:sub(start_idx))
            end
            
            -- Apply the parts to the buffer
            if #parts > 0 then
              -- First part gets appended to the last line
              lines[last_line_idx] = lines[last_line_idx] .. parts[1]
              
              -- Any additional parts create new lines
              for i = 2, #parts do
                table.insert(lines, parts[i])
              end
              
              -- Update the buffer
              pcall(vim.api.nvim_buf_set_lines, output_bufnr, 0, -1, false, lines)
            end
          end
          
          -- Make output buffer readonly again
          pcall(vim.api.nvim_buf_set_option, output_bufnr, "modifiable", false)
          
          -- Scroll output to bottom
          pcall(vim.api.nvim_win_set_cursor, output_win, {vim.api.nvim_buf_line_count(output_bufnr), 0})
        end
      end)
    end
    
    -- Define on_error callback function
    local function handle_error(error_message)
      vim.schedule(function()
        -- Stop thinking animation if it's still running
        if thinking_timer and thinking_timer:is_active() then
          thinking_timer:stop()
          thinking_timer:close()
        end
        
        -- Make output buffer modifiable temporarily
        pcall(vim.api.nvim_buf_set_option, output_bufnr, "modifiable", true)
        
        -- If the process was interrupted, show interrupted message
        if current_query and current_query.interrupted then
          -- Find the thinking line and replace it
          local lines = vim.api.nvim_buf_get_lines(output_bufnr, 0, -1, false)
          for i, line in ipairs(lines) do
            if line:match("^Assistant: Thinking") then
              lines[i] = "Assistant: [Interrupted by user]"
              break
            end
          end
          pcall(vim.api.nvim_buf_set_lines, output_bufnr, 0, -1, false, lines)
        else
          -- Show error message
          local lines = vim.api.nvim_buf_get_lines(output_bufnr, 0, -1, false)
          for i, line in ipairs(lines) do
            if line:match("^Assistant: Thinking") then
              lines[i] = "Assistant: [Error: " .. error_message .. "]"
              break
            end
          end
          pcall(vim.api.nvim_buf_set_lines, output_bufnr, 0, -1, false, lines)
          
          -- Notify user
          vim.notify("Claude API Error: " .. error_message, vim.log.levels.ERROR)
        end
        
        -- Add separator after response
        pcall(vim.api.nvim_buf_set_lines, output_bufnr, -1, -1, false, {"", "---", ""})
        
        -- Make output buffer readonly again
        pcall(vim.api.nvim_buf_set_option, output_bufnr, "modifiable", false)
        
        -- Scroll output to bottom
        pcall(vim.api.nvim_win_set_cursor, output_win, {vim.api.nvim_buf_line_count(output_bufnr), 0})
        
        -- Make sure input buffer is modifiable
        pcall(vim.api.nvim_buf_set_option, input_bufnr, "modifiable", true)
        
        -- Focus input window again and enter insert mode
        pcall(vim.api.nvim_set_current_win, input_win)
        vim.cmd("startinsert")
        
        -- Clear current query reference
        M.state.current_query = nil
        M.state.sidebar_job_id = nil
      end)
    end
    
    -- Use mcp_request to make the API call
    M.state.sidebar_job_id = mcp.request(
      input_text,
      handle_complete,
      handle_chunk,
      handle_error
    )
  end
  
  -- Function to interrupt current query
  local function interrupt_query()
    if M.state.sidebar_job_id and vim.fn.jobwait({M.state.sidebar_job_id}, 0)[1] == -1 then
      -- Mark as interrupted for the exit handler
      if M.state.current_query then
        M.state.current_query.interrupted = true
      end
      
      -- Kill the job
      vim.fn.jobstop(M.state.sidebar_job_id)
      M.state.sidebar_job_id = nil
      
      -- Ensure input buffer is modifiable
      pcall(vim.api.nvim_buf_set_option, input_bufnr, "modifiable", true)
      
      -- Notify user
      vim.notify("Query interrupted", vim.log.levels.INFO)
    end
  end
  
  -- Set up keymaps for input buffer
  -- Map Enter to submit query, Shift+Enter to create a new line
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "i",
    "<CR>",
    "<Esc>:lua require('claude-code').submit_sidebar_query()<CR>a",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "i",
    "<S-CR>",
    "<CR>",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "n",
    "<CR>",
    ":lua require('claude-code').submit_sidebar_query()<CR>",
    { noremap = true, silent = true }
  )
  
  -- Map close key
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "n",
    cfg.mappings.close,
    ":lua require('claude-code').close()<CR>",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    output_bufnr,
    "n",
    cfg.mappings.close,
    ":lua require('claude-code').close()<CR>",
    { noremap = true, silent = true }
  )
  
  -- Map Escape key to interrupt current query
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "n",
    "<Esc>",
    ":lua require('claude-code').interrupt_sidebar_query()<CR>",
    { noremap = true, silent = true }
  )
  
  -- Map in insert mode - but first restore modifiable in case it prevents typing
  vim.api.nvim_buf_set_keymap(
    input_bufnr,
    "i",
    "<Esc>",
    "<Esc>:lua vim.api.nvim_buf_set_option(vim.api.nvim_get_current_buf(), 'modifiable', true); require('claude-code').interrupt_sidebar_query()<CR>",
    { noremap = true, silent = true }
  )
  
  vim.api.nvim_buf_set_keymap(
    output_bufnr,
    "n",
    "<Esc>",
    ":lua require('claude-code').interrupt_sidebar_query()<CR>",
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
  
  -- Save state
  M.state.output_bufnr = output_bufnr
  M.state.output_win = output_win
  M.state.input_bufnr = input_bufnr 
  M.state.input_win = input_win
  
  -- Return handlers for use in main module
  return {
    submit_query = submit_query,
    interrupt_query = interrupt_query,
    input_bufnr = input_bufnr,
    output_bufnr = output_bufnr
  }
end

-- Submit a query
function M.submit_sidebar_query()
  -- Just forward to the closure we created during setup
  if M.submit_query_func then
    M.submit_query_func()
  end
end

-- Interrupt a query
function M.interrupt_sidebar_query()
  -- Check if there's a query in progress
  if M.state.sidebar_job_id and vim.fn.jobwait({M.state.sidebar_job_id}, 0)[1] == -1 then
    -- Mark as interrupted for the exit handler
    if M.state.current_query then
      M.state.current_query.interrupted = true
    end
    
    -- Kill the job
    vim.fn.jobstop(M.state.sidebar_job_id)
    M.state.sidebar_job_id = nil
    
    -- Ensure input buffer is modifiable
    if M.state.input_bufnr and vim.api.nvim_buf_is_valid(M.state.input_bufnr) then
      pcall(vim.api.nvim_buf_set_option, M.state.input_bufnr, "modifiable", true)
    end
    
    -- Notify user
    vim.notify("Query interrupted", vim.log.levels.INFO)
  end
end

return M
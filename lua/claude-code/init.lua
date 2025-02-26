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
      border = "rounded", -- Border style: "none", "single", "double", "rounded", "solid", or "shadow"
      output = "nowrap" -- Text display in output buffer: "wrap" or "nowrap" (default)
    }
  },
  command = "claude",  -- Assumes claude cli is in path
  no_stream = false,   -- Use streaming mode by default (set to true for newer Claude CLI that supports --no-stream)
  mappings = {
    close = "<leader><Esc>",  -- Key to exit and close the window
  },
  mcp = {
    enabled = true,    -- Use MCP for sidebar mode instead of Claude CLI
    model = "claude-3-7-sonnet-20240229",  -- Default to latest Claude 3.7 Sonnet model
    api_key = nil,     -- API key for Anthropic API (set to nil to use ANTHROPIC_API_KEY env variable)
    max_tokens = 8000, -- Maximum tokens to generate (increased for more comprehensive responses)
    temperature = 0.3, -- Lower temperature for more deterministic code generation
    include_context = true, -- Whether to include git repo code context with requests
    max_context_files = 20, -- Maximum number of files to include in context (reduce if hitting token limits)
    max_file_size = 100000, -- Maximum size of individual files to include in context (in bytes)
  }
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


-- Check if Claude CLI is available
function M.is_claude_available()
  local handle = io.popen("command -v " .. M.config.command .. " 2>/dev/null")
  local result = handle:read("*a")
  handle:close()
  return result:gsub("%s+", "") ~= ""
end

-- Open Claude CLI based on configured mode
function M.open()
  if M.config.mode == "terminal" then
    -- For terminal mode, we still use the Claude CLI
    if not M.is_claude_available() then
      vim.notify("Claude CLI not found in PATH. Please make sure '" .. M.config.command .. "' is installed and available.", vim.log.levels.ERROR)
      return
    end
    M.open_terminal()
  elseif M.config.mode == "sidebar" then
    -- For sidebar mode, we use MCP instead of CLI, no need to check for CLI availability
    M.open_sidebar()
  else
    vim.notify("Unsupported mode: " .. M.config.mode, vim.log.levels.ERROR)
  end
end

-- Helper function to check if the curl command is available
function M.is_curl_available()
  local handle = io.popen("command -v curl 2>/dev/null")
  local result = handle:read("*a")
  handle:close()
  return result:gsub("%s+", "") ~= ""
end

-- Helper function to get the Anthropic API key (either from config or environment)
function M.get_api_key()
  -- Try to get from config first
  if M.config.mcp.api_key then
    return M.config.mcp.api_key
  end
  
  -- Try to get from environment variable
  local handle = io.popen("echo $ANTHROPIC_API_KEY")
  local key = handle:read("*a"):gsub("%s+$", "")
  handle:close()
  
  if key ~= "" then
    return key
  end
  
  -- Not found
  return nil
end

-- Helper function to get project root directory (git root or cwd fallback)
function M.get_project_root()
  -- Try to get git root first
  local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
  local result = handle and handle:read("*a"):gsub("%s+$", "") or ""
  handle:close()
  
  -- If git root was found, return it
  if result ~= "" then
    return result
  end
  
  -- Otherwise fallback to current working directory
  handle = io.popen("pwd")
  result = handle and handle:read("*a"):gsub("%s+$", "") or ""
  handle:close()
  
  return result
end

-- Helper function to determine file language for proper syntax highlighting
function M.get_file_language(filename)
  local extension_map = {
    -- Common extensions
    [".lua"] = "lua",
    [".js"] = "javascript",
    [".jsx"] = "jsx",
    [".ts"] = "typescript",
    [".tsx"] = "tsx",
    [".py"] = "python",
    [".rb"] = "ruby",
    [".php"] = "php",
    [".c"] = "c",
    [".h"] = "c",
    [".cpp"] = "cpp",
    [".hpp"] = "cpp",
    [".cs"] = "csharp",
    [".java"] = "java",
    [".kt"] = "kotlin",
    [".go"] = "go",
    [".rs"] = "rust",
    [".swift"] = "swift",
    [".sh"] = "bash",
    [".bash"] = "bash",
    [".zsh"] = "bash",
    [".json"] = "json",
    [".yaml"] = "yaml",
    [".yml"] = "yaml",
    [".toml"] = "toml",
    [".xml"] = "xml",
    [".html"] = "html",
    [".css"] = "css",
    [".scss"] = "scss",
    [".md"] = "markdown",
    [".markdown"] = "markdown",
    [".vim"] = "vim",
    [".pl"] = "perl",
    [".scala"] = "scala",
    [".dart"] = "dart",
    [".ex"] = "elixir",
    [".exs"] = "elixir",
    [".erl"] = "erlang",
    [".hs"] = "haskell",
    [".clj"] = "clojure",
    [".sql"] = "sql",
    [".r"] = "r",
  }
  
  -- Match by extension
  local ext = filename:match("%.%w+$")
  if ext and extension_map[ext:lower()] then
    return extension_map[ext:lower()]
  end
  
  -- Match special files
  if filename:match("Dockerfile$") then
    return "dockerfile"
  elseif filename:match("Makefile$") then
    return "makefile"
  elseif filename:match("CMakeLists%.txt$") then
    return "cmake"
  end
  
  -- Default to text if no match found
  return ""
end

-- Helper function to parse and apply code edits formatted for automatic application
function M.apply_code_edits(text)
  -- Patterns to match edit-file and new-file blocks
  local edit_file_pattern = "```edit%-file: ([^\n]+)[\n\r]+(.-)\n```[\n\r]+```replacement[\n\r]+(.-)\n```"
  local new_file_pattern = "```new%-file: ([^\n]+)[\n\r]+(.-)\n```"
  
  local project_root = M.get_project_root()
  local changes_made = false
  local results = {}
  
  -- Process edit-file blocks
  for file_path, original, replacement in text:gmatch(edit_file_pattern) do
    -- Remove carriage returns if any
    original = original:gsub("\r", "")
    replacement = replacement:gsub("\r", "")
    
    -- Construct absolute path
    local abs_path = project_root .. "/" .. file_path
    
    -- Try to read the file
    local file = io.open(abs_path, "r")
    if not file then
      table.insert(results, {
        success = false,
        file = file_path,
        message = "Could not open file for reading"
      })
    else
      local content = file:read("*a")
      file:close()
      
      -- Check if the original text exists in the file
      if not content:find(original, 1, true) then
        table.insert(results, {
          success = false,
          file = file_path,
          message = "Original text not found in the file"
        })
      else
        -- Replace the text
        local new_content = content:gsub(original, replacement, 1)
        
        -- Write the new content back to the file
        file = io.open(abs_path, "w")
        if not file then
          table.insert(results, {
            success = false,
            file = file_path,
            message = "Could not open file for writing"
          })
        else
          file:write(new_content)
          file:close()
          
          table.insert(results, {
            success = true,
            file = file_path,
            message = "Edit applied successfully"
          })
          changes_made = true
        end
      end
    end
  end
  
  -- Process new-file blocks
  for file_path, content in text:gmatch(new_file_pattern) do
    -- Remove carriage returns if any
    content = content:gsub("\r", "")
    
    -- Construct absolute path
    local abs_path = project_root .. "/" .. file_path
    
    -- Ensure directory exists
    local dir_path = abs_path:match("(.+)/[^/]*$")
    if dir_path then
      vim.fn.mkdir(dir_path, "p")
    end
    
    -- Create the file
    local file = io.open(abs_path, "w")
    if not file then
      table.insert(results, {
        success = false,
        file = file_path,
        message = "Could not create file"
      })
    else
      file:write(content)
      file:close()
      
      table.insert(results, {
        success = true,
        file = file_path,
        message = "File created successfully"
      })
      changes_made = true
    end
  end
  
  -- If no changes were detected, it might be because the response wasn't properly formatted
  if #results == 0 then
    return {
      success = false,
      changes_made = false,
      message = "No code edit blocks detected in the response"
    }
  end
  
  return {
    success = true,
    changes_made = changes_made,
    results = results
  }
end

-- Helper function to get code context from project directory
function M.get_code_context()
  local project_root = M.get_project_root()
  -- Continue even if no git repo found (will use current working directory)
  
  -- Get currently active buffer path if any
  local current_buffer_path = vim.fn.expand("%:p")
  local has_current_buffer = current_buffer_path ~= ""
  
  -- Get a list of source files (include all common programming languages and config files)
  local temp_file_list = os.tmpname()
  os.execute(string.format(
    "find %s -type f -size -100k -not -path \"*/\\.*\" -a \\( " ..
    "-name \"*.lua\" -o -name \"*.vim\" -o " ..
    "-name \"*.js\" -o -name \"*.jsx\" -o -name \"*.ts\" -o -name \"*.tsx\" -o " ..
    "-name \"*.py\" -o -name \"*.rb\" -o -name \"*.php\" -o " ..
    "-name \"*.c\" -o -name \"*.h\" -o -name \"*.cpp\" -o -name \"*.hpp\" -o " ..
    "-name \"*.cs\" -o -name \"*.java\" -o -name \"*.kt\" -o " ..
    "-name \"*.go\" -o -name \"*.rs\" -o -name \"*.swift\" -o " ..
    "-name \"*.sh\" -o -name \"*.bash\" -o -name \"*.zsh\" -o " ..
    "-name \"*.json\" -o -name \"*.yaml\" -o -name \"*.yml\" -o -name \"*.toml\" -o " ..
    "-name \"*.xml\" -o -name \"*.html\" -o -name \"*.css\" -o -name \"*.scss\" -o " ..
    "-name \"*.md\" -o -name \"*.markdown\" -o -name \"README*\" -o -name \"LICENSE*\" -o " ..
    "-name \"Makefile\" -o -name \"CMakeLists.txt\" -o -name \"Dockerfile\" " ..
    "\\) | sort > %s",
    project_root, temp_file_list
  ))
  
  local file = io.open(temp_file_list, "r")
  if not file then
    os.remove(temp_file_list)
    return nil
  end
  
  local file_paths = {}
  for line in file:lines() do
    table.insert(file_paths, line)
  end
  file:close()
  os.remove(temp_file_list)
  
  -- Use configured maximum number of files to include
  local max_files = M.config.mcp.max_context_files
  local files_to_include = {}
  
  -- First priority: Include currently open buffer if it exists
  if has_current_buffer then
    for i, path in ipairs(file_paths) do
      if path == current_buffer_path then
        table.insert(files_to_include, path)
        table.remove(file_paths, i)
        break
      end
    end
  end
  
  -- Second priority: Always include README if it exists
  for i, path in ipairs(file_paths) do
    if path:match("/README%.md$") then
      table.insert(files_to_include, path)
      table.remove(file_paths, i)
      break
    end
  end
  
  -- Third priority: Include project configuration files
  for i = #file_paths, 1, -1 do
    local path = file_paths[i]
    if path:match("package%.json$") or path:match("%.gemspec$") or 
       path:match("setup%.py$") or path:match("Makefile$") or 
       path:match("Cargo%.toml$") or path:match("%.rockspec$") or
       path:match("CMakeLists%.txt$") or path:match("%.cabal$") or
       path:match("%.csproj$") or path:match("pom%.xml$") or
       path:match("Dockerfile$") or path:match("tsconfig%.json$") or
       path:match("%.gradle$") or path:match("build%.sbt$") or
       path:match("%.pro$") or path:match("%.podspec$") then
      table.insert(files_to_include, path)
      table.remove(file_paths, i)
      if #files_to_include >= max_files then
        break
      end
    end
  end
  
  -- Fourth priority: Include main source files (various languages)
  for i = #file_paths, 1, -1 do
    local path = file_paths[i]
    -- Common patterns for important source files across languages
    if path:match("main%.%w+$") or path:match("app%.%w+$") or
       path:match("index%.%w+$") or path:match("server%.%w+$") or
       path:match("core%.%w+$") or path:match("common%.%w+$") or
       path:match("utils%.%w+$") or path:match("helpers%.%w+$") or
       path:match("/src/") or path:match("/lib/") or
       -- Language-specific module systems
       path:match("/plugin/.*%.lua$") or path:match("/lua/.*/init%.lua$") or
       path:match("__init__%.py$") or path:match("index%.js$") or 
       path:match("index%.ts$") or path:match("mod%.rs$") or
       path:match("package%.scala$") then
      table.insert(files_to_include, path)
      table.remove(file_paths, i)
      if #files_to_include >= max_files then
        break
      end
    end
  end
  
  -- Fifth priority: Include test files that might contain usage examples
  for i = #file_paths, 1, -1 do
    local path = file_paths[i]
    if path:match("/test/") or path:match("/spec/") or
       path:match("/tests/") or path:match("_test%.%w+$") or
       path:match("Test%.%w+$") or path:match("%.spec%.%w+$") or
       path:match("%.test%.%w+$") then
      table.insert(files_to_include, path)
      table.remove(file_paths, i)
      if #files_to_include >= max_files then
        break
      end
    end
  end
  
  -- If we still have room, add other files
  while #files_to_include < max_files and #file_paths > 0 do
    table.insert(files_to_include, table.remove(file_paths, 1))
  end
  
  -- Read content of selected files
  local context_files = {}
  for _, path in ipairs(files_to_include) do
    local f = io.open(path, "r")
    if f then
      local content = f:read("*a")
      f:close()
      
      -- Get relative path from project root
      local rel_path = path:sub(#project_root + 2) -- +2 to account for the trailing slash
      
      -- Only include if file isn't too large (respect configured limit)
      if #content < M.config.mcp.max_file_size then
        table.insert(context_files, {
          name = rel_path,
          content = content
        })
      end
    end
  end
  
  return context_files
end

-- Make an MCP request to Anthropic API with code context
function M.mcp_request(prompt, callback, on_chunk, on_error)
  -- Check if curl is available
  if not M.is_curl_available() then
    if on_error then
      on_error("Curl not found in PATH. Please make sure 'curl' is installed and available.")
    end
    return
  end
  
  -- Get API key
  local api_key = M.get_api_key()
  if not api_key then
    if on_error then
      on_error("Anthropic API key not found. Please set it in your config or in the ANTHROPIC_API_KEY environment variable.")
    end
    return
  end
  
  -- Get code context from git repo if enabled
  local code_context = nil
  if M.config.mcp.include_context then
    code_context = M.get_code_context()
  end
  
  -- Create a temp file for the request body
  local temp_request = os.tmpname()
  local req_file = io.open(temp_request, "w")
  
  -- Create the request body
  local request_data = {
    model = M.config.mcp.model,
    max_tokens = M.config.mcp.max_tokens,
    stream = true,
    temperature = M.config.mcp.temperature  -- Use configured temperature
  }
  
  -- Add messages with code context if available
  if code_context and #code_context > 0 then
    local content = {
      { 
        type = "text",
        text = "I'm using the Claude Code NeoVim plugin. I'll share the plugin code for context, then request changes. I need specific instructions formatted for automatic code editing.\n\n" ..
               "IMPORTANT INSTRUCTIONS FOR PROVIDING CODE EDITS:\n" ..
               "1. When suggesting changes, use this strict format for each file to modify:\n\n" ..
               "```edit-file: path/to/file.ext\n" ..
               "// Original code with enough context (at least 3-5 lines before and after)\n" ..
               "original code here...\n" ..
               "```\n\n" ..
               "```replacement\n" ..
               "// New code that should replace the above\n" ..
               "new code here...\n" ..
               "```\n\n" ..
               "2. The file path must be relative to the project root and match exactly\n" ..
               "3. The original code must match exactly what's in the file (including whitespace and indentation)\n" ..
               "4. The replacement code must be complete (no placeholders like <...> or ...)\n" ..
               "5. Ensure the edit can be made precisely - the original code must be unique in the file\n" ..
               "6. If needed, include multiple edit blocks to make multiple changes to the same file\n" ..
               "7. For new files, use this format:\n\n" ..
               "```new-file: path/to/new/file.ext\n" ..
               "// Content for the new file\n" ..
               "new file content here...\n" ..
               "```\n\n" ..
               "8. Keep any explanations brief and focused on implementation details\n" ..
               "9. If my request involves existing code, take all source context files into account\n\n" ..
               "Below is the relevant source code for context:\n\n"
      }
    }
    
    -- Add code files as content blocks
    for _, file in ipairs(code_context) do
      table.insert(content, {
        type = "text",
        text = "File: " .. file.name .. "\n\n```" .. M.get_file_language(file.name) .. "\n" .. file.content .. "\n```\n\n"
      })
    end
    
    -- Add the actual prompt
    table.insert(content, {
      type = "text",
      text = "\nMy request is:\n\n" .. prompt .. "\n\nProvide properly formatted edit blocks that can be automatically applied to my code."
    })
    
    request_data.messages = {
      { role = "user", content = content }
    }
  else
    -- Simple message without code context
    request_data.messages = {
      { role = "user", content = prompt }
    }
  end
  
  -- Encode the request data as JSON
  local request_body = vim.json.encode(request_data)
  req_file:write(request_body)
  req_file:close()
  
  -- Create a shell script that will make the request
  local temp_script = os.tmpname() .. ".sh"
  local script_file = io.open(temp_script, "w")
  
  script_file:write([[
#!/bin/sh
curl -s -N \
  -H "x-api-key: ]] .. api_key .. [[" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d @]] .. temp_request .. [[ \
  https://api.anthropic.com/v1/messages
  
rm -f ]] .. temp_request .. [[ # Clean up the request file
]])
  
  script_file:close()
  os.execute("chmod +x " .. temp_script)
  
  -- Variable to accumulate the complete response
  local complete_response = ""
  
  -- Start job to run the API request
  local job_id = vim.fn.jobstart(temp_script, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line:sub(1, 6) == "data: " then
            local json_str = line:sub(7)
            
            -- Skip "[DONE]" message at end
            if json_str == "[DONE]" then
              return
            end
            
            -- Try to parse the JSON
            local success, parsed = pcall(vim.json.decode, json_str)
            if success and parsed and parsed.type == "content_block_delta" then
              local content = parsed.delta and parsed.delta.text or ""
              
              -- Add to complete response
              complete_response = complete_response .. content
              
              -- Call the on_chunk callback if provided
              if on_chunk then
                on_chunk(content)
              end
            end
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        -- Clean up
        pcall(os.remove, temp_script)
        
        -- Call the completion callback
        if exit_code == 0 then
          if callback then
            callback(complete_response)
          end
        else
          if on_error then
            on_error("API request failed with exit code " .. exit_code)
          end
        end
      end)
    end
  })
  
  -- Return the job ID for potential cancellation
  return job_id
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

-- Open Claude sidebar with input and output buffers using MCP API
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
  local should_wrap = M.config.window.sidebar.output == "wrap"
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
    border = M.config.window.sidebar.border,
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
  
  -- Display a minimal welcome message
  vim.api.nvim_buf_set_lines(output_bufnr, 0, -1, false, {
    "Initializing Claude CLI...",
    ""
  })
  
  -- Set output buffer as modifiable for initialization
  vim.api.nvim_buf_set_option(output_bufnr, "modifiable", true)
  
  -- Display a welcome message
  vim.api.nvim_buf_set_lines(output_bufnr, 0, -1, false, {
    "Initializing Claude API...",
    ""
  })
  
  -- Check if curl is available for API requests
  if not M.is_curl_available() then
    vim.api.nvim_buf_set_lines(output_bufnr, -1, -1, false, {
      "Error: curl command not found in PATH. Please install curl to use the MCP sidebar mode.",
      "",
      "---",
      "",
      "Falling back to terminal mode for Claude interactions. To use:",
      "1. Close this window with " .. M.config.mappings.close,
      "2. Ensure curl is installed",
      "3. Restart Claude Code"
    })
    
    vim.api.nvim_buf_set_option(output_bufnr, "modifiable", false)
    return
  end
  
  -- Check if API key is available
  local api_key = M.get_api_key()
  if not api_key then
    vim.api.nvim_buf_set_lines(output_bufnr, -1, -1, false, {
      "Error: Anthropic API key not found.",
      "Please set your API key in one of the following ways:",
      "",
      "1. In your init.lua config:",
      "   require('claude-code').setup({",
      "     mcp = {",
      "       api_key = 'your-api-key-here'",
      "     }",
      "   })",
      "",
      "2. As an environment variable:",
      "   export ANTHROPIC_API_KEY=your-api-key-here",
      "",
      "---",
      "",
      "Press " .. M.config.mappings.close .. " to close the sidebar."
    })
    
    vim.api.nvim_buf_set_option(output_bufnr, "modifiable", false)
    return
  end
  
  -- Add welcome message and usage instructions
  vim.api.nvim_buf_set_lines(output_bufnr, 0, -1, false, {
    "Claude API initialized successfully!",
    "Using model: " .. M.config.mcp.model,
    "",
    "---",
    "",
    "Type your queries in the input box below and press Enter to submit.",
    "Press Shift+Enter to add a new line in the input.",
    "Press Esc to interrupt a running query.",
    "Use Ctrl+h/j/k/l to navigate between windows.",
    "Press " .. M.config.mappings.close .. " to close the sidebar.",
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
  
  -- Make the input buffer ready but don't disable it - we'll handle this differently
  vim.api.nvim_buf_set_option(input_bufnr, "modifiable", true)
  
  -- Focus input window immediately and enter insert mode
  vim.api.nvim_set_current_win(input_win)
  vim.cmd("startinsert")
  
  -- Function to handle submit action with MCP
  local function submit_query()
    -- Check if a query is already in progress
    if M.sidebar_job_id and vim.fn.jobwait({M.sidebar_job_id}, 0)[1] == -1 then
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
    
    -- Append user query to output buffer in a format similar to Claude CLI
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
    M.thinking_timer = thinking_timer
    
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
    local response_line = current_lines + 2 -- Line with "Assistant: Thinking..."
    
    -- Store current job and timer info for interruption
    local current_query = {
      timer = thinking_timer,
      response_line = response_line,
      thinking_line = thinking_line,
      interrupted = false
    }
    M.current_query = current_query
    
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
        local edits_result = M.apply_code_edits(full_response)
        
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
        M.current_query = nil
        M.sidebar_job_id = nil
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
        M.current_query = nil
        M.sidebar_job_id = nil
      end)
    end
    
    -- Use mcp_request to make the API call
    M.sidebar_job_id = M.mcp_request(
      input_text,
      handle_complete,
      handle_chunk,
      handle_error
    )
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
  
  -- Function to interrupt current query
  local function interrupt_query()
    if M.sidebar_job_id and vim.fn.jobwait({M.sidebar_job_id}, 0)[1] == -1 then
      -- Mark as interrupted for the exit handler
      if M.current_query then
        M.current_query.interrupted = true
      end
      
      -- Kill the job
      vim.fn.jobstop(M.sidebar_job_id)
      M.sidebar_job_id = nil
      
      -- Ensure input buffer is modifiable
      pcall(vim.api.nvim_buf_set_option, input_bufnr, "modifiable", true)
      
      -- Notify user
      vim.notify("Query interrupted", vim.log.levels.INFO)
    end
  end
  
  -- Expose the interrupt function globally
  M.interrupt_sidebar_query = interrupt_query
  
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


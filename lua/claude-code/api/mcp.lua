local M = {}
local utils = require("claude-code.utils")
local config = require("claude-code.core.config")

-- Helper function to get API key (either from config or environment)
function M.get_api_key()
  local cfg = config.get("mcp")
  -- Try to get from config first
  if cfg.api_key then
    return cfg.api_key
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

-- Helper function to get code context from project directory
function M.get_code_context()
  local cfg = config.get("mcp")
  local project_root = utils.get_project_root()
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
  local max_files = cfg.max_context_files
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
      if #content < cfg.max_file_size then
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
function M.request(prompt, callback, on_chunk, on_error)
  -- Check if curl is available
  if not utils.is_curl_available() then
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
  
  local cfg = config.get("mcp")
  
  -- Get code context from git repo if enabled
  local code_context = nil
  if cfg.include_context then
    code_context = M.get_code_context()
  end
  
  -- Create a temp file for the request body
  local temp_request = os.tmpname()
  local req_file = io.open(temp_request, "w")
  
  -- Create the request body
  local request_data = {
    model = cfg.model,
    max_tokens = cfg.max_tokens,
    stream = true,
    temperature = cfg.temperature,  -- Use configured temperature
    system = "You are Claude Code, Anthropic's official CLI for Claude.\n\nYou are an interactive CLI tool that helps users with software engineering tasks. Use the instructions below and the tools available to you to assist the user.\n\nIMPORTANT: You should be concise, direct, and to the point, since your responses will be displayed on a command line interface. Answer the user's question directly, without elaboration, explanation, or details. One word answers are best. Avoid introductions, conclusions, and explanations. You MUST avoid text before/after your response, such as \"The answer is <answer>.\", \"Here is the content of the file...\" or \"Based on the information provided, the answer is...\" or \"Here is what I will do next...\".\n\nAny file paths you return in your final response MUST be absolute. DO NOT use relative paths.\n\nWhen relevant, share file names and code snippets relevant to the query."
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
        text = "File: " .. file.name .. "\n\n```" .. utils.get_file_language(file.name) .. "\n" .. file.content .. "\n```\n\n"
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
  -H "anthropic-version: 2023-01-01" \
  -H "content-type: application/json" \
  -d @]] .. temp_request .. [[ \
  "https://api.anthropic.com/v1/messages?stream=true"
  
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
            
            -- Debug: Write the raw response to a log file
            local debug_file = io.open("/tmp/claude_api_debug.log", "a")
            if debug_file then
              debug_file:write("Raw JSON: " .. json_str .. "\n\n")
              debug_file:close()
            end
            
            if success then
              -- Handle various Claude API streaming response formats
              local content = ""
              
              -- Claude API response formats
              -- First check for delta with content blocks (current API)
              if parsed.delta and parsed.delta.text then
                content = parsed.delta.text
              elseif parsed.type == "content_block_delta" then 
                content = parsed.delta and parsed.delta.text or ""
              elseif parsed.type == "content_block_start" then
                content = ""  -- Just a marker, no actual content
              elseif parsed.type == "content_block_stop" then
                content = ""  -- Just a marker, no actual content
              elseif parsed.delta and parsed.delta.content then
                if type(parsed.delta.content) == "table" and #parsed.delta.content > 0 then
                  content = parsed.delta.content[1].text or ""
                elseif type(parsed.delta.content) == "string" then
                  content = parsed.delta.content
                end
              elseif parsed.content and parsed.content[1] and parsed.content[1].text then
                content = parsed.content[1].text
              end
              
              -- Debug: Log the extraction method and content
              local debug_file = io.open("/tmp/claude_api_debug.log", "a")
              if debug_file then
                -- Log which path was used for extraction
                local extraction_path = "unknown"
                if parsed.delta and parsed.delta.text then
                  extraction_path = "delta.text"
                elseif parsed.type == "content_block_delta" then
                  extraction_path = "content_block_delta"
                elseif parsed.type == "content_block_start" then
                  extraction_path = "content_block_start"
                elseif parsed.type == "content_block_stop" then
                  extraction_path = "content_block_stop"
                elseif parsed.delta and parsed.delta.content then
                  if type(parsed.delta.content) == "table" then
                    extraction_path = "delta.content[array]"
                  else
                    extraction_path = "delta.content[string]"
                  end
                elseif parsed.content and parsed.content[1] and parsed.content[1].text then
                  extraction_path = "content[1].text"
                end
                
                -- Log the extraction details
                debug_file:write("Path: " .. extraction_path .. ", Content: " .. (content or "nil") .. "\n")
                
                -- If no content was extracted, log the entire parsed object
                if content == "" then
                  debug_file:write("No content extracted. Full parsed object:\n")
                  debug_file:write(vim.inspect(parsed) .. "\n\n")
                end
                
                debug_file:close()
              end
              
              if content ~= "" then
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

return M
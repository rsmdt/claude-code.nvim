local M = {}
local utils = require("claude-code.utils")

-- Helper function to parse and apply code edits formatted for automatic application
function M.apply_code_edits(text)
  -- Patterns to match edit-file and new-file blocks
  local edit_file_pattern = "```edit%-file: ([^\n]+)[\n\r]+(.-)\n```[\n\r]+```replacement[\n\r]+(.-)\n```"
  local new_file_pattern = "```new%-file: ([^\n]+)[\n\r]+(.-)\n```"
  
  local project_root = utils.get_project_root()
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

return M
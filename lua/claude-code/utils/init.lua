local M = {}

-- Helper function to check if the curl command is available
function M.is_curl_available()
  local handle = io.popen("command -v curl 2>/dev/null")
  local result = handle:read("*a")
  handle:close()
  return result:gsub("%s+", "") ~= ""
end

-- Helper function to check if Claude CLI is available
function M.is_claude_available()
  local config = require("claude-code.core.config").get()
  local handle = io.popen("command -v " .. config.command .. " 2>/dev/null")
  local result = handle:read("*a")
  handle:close()
  return result:gsub("%s+", "") ~= ""
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

return M
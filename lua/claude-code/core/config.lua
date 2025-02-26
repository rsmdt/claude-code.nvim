local M = {}

-- Default configuration
local config = {
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

-- Setup function to override defaults with user config
function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Get the complete config or a specific value
function M.get(key)
  if key then
    return config[key]
  end
  return config
end

return M
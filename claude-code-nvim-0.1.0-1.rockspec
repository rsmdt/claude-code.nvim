package = "claude-code-nvim"
version = "0.1.0-1"
source = {
   url = "git+https://github.com/irudi/claude-code.nvim.git"
}
description = {
   summary = "Claude Code CLI experience within Neovim",
   detailed = [[
      A minimal Neovim plugin that launches the Claude Code CLI in a terminal split.
      Simple integration for using Claude Code within your editor.
   ]],
   homepage = "https://github.com/irudi/claude-code.nvim",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      ["claude-code"] = "lua/claude-code/init.lua"
   }
}
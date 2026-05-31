require("wataru.core")
require("wataru.lazy")
require("wataru.lsp")

-- Reload files changed on disk automatically
vim.opt.autoread = true

-- Trigger the check to focus/buffer events and cursor idle
vim.api.nvim_create_autocmd(
  { "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" },
  { pattern = "*", command = "checktime" }
)

-- Fire CursorHold faster (default is 4000ms - too slow)
vim.opt.updatetime = 500

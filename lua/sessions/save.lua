-- credits to @Malace : https://www.reddit.com/r/neovim/comments/ql4iuj/rename_hover_including_window_title_and/
-- This is modified version of the above snippet

local M = {}

M.open = function()
  local col = vim.api.nvim_win_get_width(0) / 2 - 12
  local line = vim.api.nvim_win_get_height(0) / 2

  local win = require("plenary.popup").create("temp", {
    title = "Save Session",
    style = "minimal",
    borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
    relative = "cursor",
    borderhighlight = "RenamerBorder",
    titlehighlight = "RenamerTitle",
    focusable = true,
    width = 25,
    height = 1,
    line = line,
    col = col,
  })

  local map_opts = { noremap = true, silent = true }

  vim.cmd("normal w")
  vim.cmd("startinsert")

  vim.api.nvim_buf_set_keymap(0, "i", "<Esc>", "<cmd>stopinsert | q!<CR>", map_opts)
  vim.api.nvim_buf_set_keymap(0, "n", "<Esc>", "<cmd>stopinsert | q!<CR>", map_opts)

  vim.api.nvim_buf_set_keymap(
    0,
    "i",
    "<CR>",
    "<cmd>stopinsert | lua require'sessions.save'.apply(" .. win .. ")<CR>",
    map_opts
  )

  vim.api.nvim_buf_set_keymap(
    0,
    "n",
    "<CR>",
    "<cmd>stopinsert | lua require'sessions.save'.apply(" .. win .. ")<CR>",
    map_opts
  )
end

M.apply = function(win)
  local session_name = vim.trim(vim.fn.getline("."))
  vim.api.nvim_win_close(win, true)

  if #session_name > 0 and session_name ~= "" then
    require("sessions").save(session_name)
  end
end

return M

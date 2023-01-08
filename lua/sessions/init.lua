local sep
if vim.fn.has("win32") == 1 then
  sep = "\\"
else
  sep = "/"
end

-- default configuration
local config = {
  -- events which trigger a session save
  events = { "VimLeavePre" },

  -- default session filepath
  session_filepath = vim.fn.stdpath("data") .. sep .. "sessions",
}

local M = {}

local get_session_path = function(name)
  return vim.fn.fnamemodify(config.session_filepath, ":p") .. sep .. name .. ".vim"
end

local session_file_path = nil

local write_session_file = function()
  local present, view = pcall(require, "nvim-tree.view")

  if not present then
    vim.cmd(string.format("mksession! %s", session_file_path))
    return
  end

  local api = require("nvim-tree.api")
  local restore = false
  if view.is_visible() then
    restore = true
    api.tree.close()
  end

  vim.cmd(string.format("mksession! %s", session_file_path))

  if restore then
    api.tree.open()
  end
end

-- start autosaving changes to the session file
local start_autosave = function()
  -- save future changes
  local events = vim.fn.join(config.events, ",")
  local augroup = vim.api.nvim_create_augroup("sessions.nvim", {})
  vim.api.nvim_create_autocmd(string.format("%s", events), {
    group = augroup,
    pattern = "*",
    callback = write_session_file,
  })
end

---save or overwrite a session file to the given path
---@param name string|nil
M.save = function(name)
  if name == nil then
    if not session_file_path then
      vim.notify("sessions.nvim: you must specify a session name.")
      return false
    end
  else
    session_file_path = get_session_path(name)
  end
  write_session_file()

  start_autosave()
  return true
end

---load a session file from the given path
---@param name string|nil
---@return boolean
M.load = function(name)
  local path = get_session_path(name)
  if not path or vim.fn.filereadable(path) == 0 then
    vim.notify(string.format("sessions.nvim: file '%s' does not exist.", path))
    return false
  end

  session_file_path = path
  vim.cmd(string.format("silent! source %s", session_file_path))
  start_autosave()

  return true
end

M.loadlast = function()
  if session_file_path ~= nil then
    vim.notify(string.format("sessions.nvim: you are working in a session yet."))
    return
  end

  local latest_session = { session = nil, last_edited = 0 }

  for _, filename in ipairs(vim.fn.readdir(config.session_filepath)) do
    local session = config.session_filepath .. sep .. filename
    local last_edited = vim.fn.getftime(session)

    if last_edited > latest_session.last_edited then
      latest_session.session = session
      latest_session.last_edited = last_edited
    end
  end

  if latest_session.session == nil then
    vim.notify(string.format("sessions.nvim: no session saved."))
    return
  end

  session_file_path = latest_session.session
  vim.cmd(string.format("silent! source %s", session_file_path))
  start_autosave()
end

M.get_workdir = function(name)
  local path = get_session_path(name)
  local f = io.open(path, "r")
  if f == nil then
    return ""
  end

  local ret = ""
  for line in f:lines("*l") do
    if line then
      local dir = line:match("cd%s+(.*)")
      if dir ~= nil then
        ret = dir
        break
      end
    end
  end

  io.close(f)
  return ret
end

M.loadlist = function()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local sessions = {}
  for _, path in ipairs(vim.fn.readdir(config.session_filepath)) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    local workdir = M.get_workdir(name)
    table.insert(sessions, { name, workdir })
  end

  local list_sessions = function(opts)
    opts = opts or {}
    pickers.new(opts, {
      prompt_title = "My Sessions",
      finder = finders.new_table({
        results = sessions,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry[1] .. " (" .. entry[2] .. ")",
            ordinal = entry[1],
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          M.load(selection.ordinal)
        end)
        return true
      end,
    }):find()
  end

  list_sessions(
    require("telescope.themes").get_dropdown({
      layout_strategy = "horizontal",
      layout_config = { horizontal = {
        prompt_position = "top",
      }, width = 0.5 },
    })
  )
end

M.setup = function()
  -- register commands
  vim.cmd([[
    command! -nargs=? SessionsSave lua require("sessions").save(<f-args>)
    command! -nargs=0 SessionsLoadLast lua require("sessions").loadlast()
    command! -nargs=1 SessionsLoad lua require("sessions").load(<f-args>)
    ]])
end

return M

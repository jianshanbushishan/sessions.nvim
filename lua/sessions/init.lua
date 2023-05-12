local levels = vim.log.levels

local M = {
  save_path = vim.fn.stdpath("data") .. "/sessions/",
  cur_session = nil,
  session_name = "",
  plugin = "Session.nvim",
}

M.get_path = function(name)
  return M.save_path .. name .. ".vim"
end

M.get_shada_path = function(name)
  return vim.fn.stdpath("data") .. "/shada/" .. name .. ".shada"
end

local close_diffview = function()
  local tabs = vim.api.nvim_list_tabpages()
  if #tabs == 1 then
    return
  end

  local present, lazy = pcall(require, "diffview.lazy")
  if not present then
    return
  end

  local lib = lazy.require("diffview.lib")
  local view = lib.get_current_view()
  if view ~= nil then
    view:close()
    lib.dispose_view(view)
  end
end

M.write_session = function()
  close_diffview()

  local present, view = pcall(require, "nvim-tree.view")

  if not present then
    vim.cmd(string.format("mksession! %s", M.cur_session))
    return
  end

  local api = require("nvim-tree.api")
  local restore = false
  if view.is_visible() then
    restore = true
    api.tree.close()
  end

  vim.cmd(string.format("mksession! %s", M.cur_session))
  vim.cmd(string.format("wshada! %s", M.get_shada_path(M.session_name)))

  if restore then
    api.tree.open()
  end
end

local set_autocmd = function()
  local augroup = vim.api.nvim_create_augroup("sessions.nvim", {})
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    pattern = "*",
    callback = M.write_session,
  })
end

M.save = function(name)
  if name == nil then
    if M.cur_session == nil then
      vim.notify(
        "sessions.nvim: you must specify a session name.",
        levels.WARN,
        { title = M.plugin }
      )
      return false
    end
    set_autocmd()
  else
    M.session_name = name
    M.cur_session = M.get_path(name)
  end

  M.write_session()
  return true
end

M.load = function(name)
  local path = M.get_path(name)
  if not path or vim.fn.filereadable(path) == 0 then
    vim.notify(
      string.format("sessions.nvim: file '%s' does not exist.", path),
      levels.WARN,
      { title = M.plugin }
    )
    return false
  end

  if M.cur_session ~= nil then
    M.save()
    vim.cmd("silent! %bd!")
    vim.cmd("clearjumps")

    local present, _ = pcall(require, "lspconfig")
    if present then
      local clients = vim.lsp.get_active_clients()
      for _, client in ipairs(clients) do
        client.stop(true)
      end
    end
  end

  M.doload(path, name)
  return true
end

M.doload = function(path, name)
  M.cur_session = path
  M.session_name = name

  local workdir = M.get_workdir(M.session_name)
  workdir = vim.fs.normalize(workdir)
  local project_settings = workdir .. "/project.vim"
  if vim.fn.filereadable(project_settings) ~= 0 then
    vim.cmd(string.format("silent! source %s", project_settings))
    print("load project settings ok!")
  end

  vim.cmd(string.format("silent! source %s", M.cur_session))
  local shada_path = M.get_shada_path(M.session_name)
  if vim.fn.filereadable(shada_path) > 0 then
    vim.cmd("delmarks A-Z")
    vim.fn.histdel(":")
    vim.fn.histdel("/")
    vim.fn.histdel("=")
    vim.fn.histdel("@")
    vim.fn.histdel(">")
    vim.cmd(string.format("rshada! %s", shada_path))
  end
  set_autocmd()

  vim.notify(
    string.format("load session '" .. name .. "' ok!"),
    levels.INFO,
    { title = M.plugin }
  )

  vim.defer_fn(function()
    vim.cmd("stopinsert")
  end, 50)

  local present, _ = pcall(require, "lspconfig")
  if present then
    vim.defer_fn(function()
      vim.cmd("LspStart")
    end, 100)
  end
end

M.loadlast = function()
  if M.cur_session ~= nil then
    vim.notify(
      string.format("sessions.nvim: you are working in a session yet."),
      levels.WARN,
      { title = M.plugin }
    )
    return
  end

  local latest_session = { session = nil, last_edited = 0, name = "" }

  for _, filename in ipairs(vim.fn.readdir(M.save_path)) do
    local session = M.save_path .. filename
    local last_edited = vim.fn.getftime(session)

    if last_edited > latest_session.last_edited then
      latest_session.session = session
      latest_session.name = filename:match("(%w+).vim")
      latest_session.last_edited = last_edited
    end
  end

  if latest_session.session == nil then
    vim.notify(
      string.format("sessions.nvim: no session saved."),
      levels.WARN,
      { title = M.plugin }
    )
    return
  end

  M.doload(latest_session.session, latest_session.name)
end

M.get_workdir = function(name)
  local path = M.get_path(name)
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

M.source = function(prompt_bufnr)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  actions.close(prompt_bufnr)
  local selection = action_state.get_selected_entry()
  M.load(selection.ordinal)
end

M.delete = function(prompt_bufnr)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  actions.close(prompt_bufnr)
  local selection = action_state.get_selected_entry()
  local session = selection.ordinal
  local path = M.get_path(session)
  vim.fn.delete(path)
  vim.notify("delete session " .. session .. " ok!", levels.INFO, { title = M.plugin })
end

M.loadlist = function()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")

  local sessions = {}
  for _, path in ipairs(vim.fn.readdir(M.save_path)) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    local workdir = M.get_workdir(name)
    table.insert(sessions, { name, workdir })
  end

  local list_sessions = function(opts)
    opts = opts or {}
    pickers
      .new(opts, {
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
        attach_mappings = function(_, map)
          actions.select_default:replace(M.source)
          map("i", "<c-d>", M.delete)
          return true
        end,
      })
      :find()
  end

  list_sessions(require("telescope.themes").get_dropdown({
    layout_strategy = "horizontal",
    layout_config = {
      horizontal = {
        prompt_position = "top",
      },
      width = 0.5,
    },
  }))
end

M.setup = function()
  vim.cmd([[
    command! -nargs=? SessionsSave lua require("sessions").save(<f-args>)
    command! -nargs=0 SessionsLoadLast lua require("sessions").loadlast()
    command! -nargs=1 SessionsLoad lua require("sessions").load(<f-args>)
    ]])
end

return M

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

M.do_write_session = function()
  vim.loop.fs_mkdir(M.save_path, 493) -- 493对应于8进制的755
  vim.cmd(string.format("mksession! %s", M.cur_session))
  vim.cmd(string.format("wshada! %s", M.get_shada_path(M.session_name)))
end

M.write_session = function()
  close_diffview()

  local present, view = pcall(require, "nvim-tree.view")

  if not present then
    M.do_write_session()
    return
  end

  local api = require("nvim-tree.api")
  local restore = false
  if view.is_visible() then
    restore = true
    api.tree.close()
  end

  M.do_write_session()

  if restore then
    api.tree.find_file({ focus = false, open = true })
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
      vim.notify("sessions.nvim: you must specify a session name.", levels.WARN, { title = M.plugin })
      return false
    end
  else
    M.session_name = name
    M.cur_session = M.get_path(name)
  end

  set_autocmd()
  M.write_session()
  return true
end

M.load = function(name)
  local path = M.get_path(name)
  if not path or vim.fn.filereadable(path) == 0 then
    vim.notify(string.format("sessions.nvim: file '%s' does not exist.", path), levels.WARN, { title = M.plugin })
    return false
  end

  if M.cur_session ~= nil then
    if M.cur_session == path then
      return
    end

    M.save()
    local present, _ = pcall(require, "lspconfig")
    if present then
      local clients = vim.lsp.get_active_clients()
      for _, client in ipairs(clients) do
        client.stop(false)
      end
    end

    M.do_project_script(false)
    vim.cmd("clearjumps")
    vim.cmd("silent! %bd!")
  end

  vim.defer_fn(function()
    M.doload(path, name)
  end, 20)

  return true
end

M.do_project_script = function(is_enter)
  if is_enter then
    local workdir = M.get_workdir(M.session_name)
    workdir = vim.fs.normalize(workdir)
    local project_settings = workdir .. "/project.lua"

    if vim.fn.filereadable(project_settings) ~= 0 then
      local m = dofile(project_settings)
      if m == nil then
        return
      end

      m.enter()
      vim.g.session_settings = m
    end
  else
    if vim.g.session_settings ~= nil then
      vim.g.session_settings.exit()
      vim.g.session_settings = nil
    end
  end
end

M.doload = function(path, name)
  M.cur_session = path
  M.session_name = name

  M.do_project_script(true)

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

  -- vim.notify(string.format("load session '" .. name .. "' ok!"), levels.INFO, { title = M.plugin })

  local present, api = pcall(require, "nvim-tree.api")
  if present then
    vim.defer_fn(function()
      api.tree.find_file({ focus = false, open = true })
    end, 100)
  end

  present, _ = pcall(require, "lspconfig")
  if present then
    vim.defer_fn(function()
      vim.cmd("LspStart")
    end, 100)
  end
end

M.loadlast = function()
  if M.cur_session ~= nil then
    vim.notify(string.format("sessions.nvim: you are working in a session yet."), levels.WARN, { title = M.plugin })
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
    vim.notify(string.format("sessions.nvim: no session saved."), levels.WARN, { title = M.plugin })
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

M.loadlist = function()
  local names = {}
  local workdirs = {}
  for _, path in ipairs(vim.fn.readdir(M.save_path)) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    local workdir = M.get_workdir(name)
    table.insert(names, name)
    workdirs[name] = workdir
  end

  vim.ui.select(names, {
    prompt = "select your session:",
    format_item = function(item)
      return string.format("%s\t\t\t%s", item, workdirs[item])
    end,
  }, function(choice)
    if choice ~= nil and choice ~= "" then
      M.load(choice)
    end
  end)
end

M.setup = function()
  vim.cmd([[
    command! -nargs=? SessionsSave lua require("sessions").save(<f-args>)
    command! -nargs=0 SessionsLoadLast lua require("sessions").loadlast()
    command! -nargs=0 SessionsLoadList lua require("sessions").loadlist()
    command! -nargs=1 SessionsLoad lua require("sessions").load(<f-args>)
    ]])
end

return M

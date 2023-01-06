local present, telescope = pcall(require, "telescope")
local session = require("sessions")
if present then
  return telescope.register_extension({
    exports = {
      sessions = session.loadlist,
    },
  })
else
  error("Cannot find telescope!")
end

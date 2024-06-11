return setmetatable({ Kbd = require('core.tty.linux.kbd') }, { __index = require('core.tty.linux.system') })

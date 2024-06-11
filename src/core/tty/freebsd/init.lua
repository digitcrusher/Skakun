return setmetatable({ Kbd = require('core.tty.freebsd.kbd') }, { __index = require('core.tty.freebsd.system') })

local here = ...
local core = require('core')
local stderr = require('core.stderr')
local tty = require('core.tty')
local utils = require('core.utils')

utils.lock_globals()
core.add_cleanup(stderr.restore)
stderr.redirect()
stderr.info(here, 'Skakun ', core.version, ' on ', core.platform)
core.add_cleanup(tty.restore)
tty.setup()

require('misc.tty_test')

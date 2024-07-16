local here = ...
local core = require('core')
local stderr = require('core.stderr')
local tty = require('core.tty')
local utils = require('core.utils')

utils.lock_globals()
core.add_cleanup(stderr.restore)
stderr.redirect()
stderr.info(here, 'Skakun ', core.version, ' on ', core.platform, ', ', os.date())

core.add_cleanup(tty.restore)
tty.setup()

local Doc = require('core.doc')
local DocView = require('core.doc_view')

local view = DocView.new(Doc.open('test'))
local rgb = utils.rgb

DocView.foreground = rgb'000000'
DocView.background = rgb'ffffff'

local old_width, old_height
while true do
  local events = tty.read_events()
  if (events[1] or {}).button == 'escape' then break end

  local width, height = tty.get_size()
  if width ~= old_width or height ~= old_height then
    tty.sync_begin()
    tty.set_background()
    tty.clear()

    local margin = 1
    view:draw(1 + 2 * margin, 1 + margin, width - 2 * margin, height - margin)
    tty.set_cursor(false)

    tty.sync_end()
    tty.flush()
  end
  old_width = width
  old_height = height

  os.execute('sleep 0.1')
end

local here = ...
local core = require('core')
local stderr = require('core.stderr')
local tty = require('core.tty')
local utils = require('core.utils')

core.should_forward_stderr_on_exit = false
utils.lock_globals()
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
  local width, height = tty.get_size()
  local should_redraw = width ~= old_width or height ~= old_height
  old_width = width
  old_height = height

  for _, event in ipairs(tty.read_events()) do
    if event.type == 'press' or event.type == 'repeat' then
      if event.button == 'escape' then
        os.exit(0)
      elseif event.button == 'left' then
        view.cursor = math.max(view.cursor - 1, 1)
      elseif event.button == 'right' then
        view.cursor = math.min(view.cursor + 1, #view.doc.buffer)
      end
      should_redraw = true
    end
  end

  if should_redraw then
    local start = os.clock()

    tty.sync_begin()
    tty.set_background()
    tty.clear()

    local margin = 1
    view:draw(1 + 2 * margin, 1 + margin, width - 2 * margin, height - margin)
    tty.set_cursor(false)

    tty.sync_end()
    tty.flush()

    stderr.info(here, 'redraw done in ', math.floor(1000000 * (os.clock() - start)), 'µs')
  end
end

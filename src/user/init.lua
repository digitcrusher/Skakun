local here = ...
local core = require('core')
local Doc = require('core.doc')
local DocView = require('core.doc_view')
local stderr = require('core.stderr')
local tty = require('core.tty')
local utils = require('core.utils')
local rgb = utils.rgb

-- core.should_forward_stderr_on_exit = false
utils.lock_globals()
core.add_cleanup(tty.restore)
tty.setup()

local view = DocView.new(Doc.open(core.args[2]))

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
      elseif event.button == 'up' then
        view.line = math.max(view.line - 1, 1)
      elseif event.button == 'scroll_up' then
        view.line = math.max(view.line - 3, 1)
      elseif event.button == 'page_up' then
        view.line = math.max(view.line - height, 1)
      elseif event.button == 'left' then
        view.col = math.max(view.col - 1, 1)
      elseif event.button == 'down' then
        view.line = view.line + 1
      elseif event.button == 'scroll_down' then
        view.line = view.line + 3
      elseif event.button == 'page_down' then
        view.line = view.line + height
      elseif event.button == 'right' then
        view.col = view.col + 1
      elseif event.button == 'w' then
        view.should_soft_wrap = not view.should_soft_wrap
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

    stderr.info(here, 'redraw done in ', math.floor(1e6 * (os.clock() - start)), 'µs')
  end
end

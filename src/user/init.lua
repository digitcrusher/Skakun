local tty = require('core.tty')
local utils = require('core.utils')

utils.lock_globals()
tty.setup()
function tty.set_window_background() end
tty.cap.window_background = false
tty.clear()
tty.set_cursor(false)

-- Everything
tty.goto(40, 10)
tty.set_foreground('black')
tty.set_background(255, 0, 191)
tty.set_bold(true)
tty.set_italic(true)
tty.set_underline(true)
tty.set_underline_color('red')
tty.set_underline_shape('curly')
tty.set_strikethrough(true)
tty.set_hyperlink('https://example.com/')
tty.write('czesc okej!!!')
tty.reset()
tty.goto(1, 1)

-- True colors
local function hue_color(hue)
  return math.floor(255 * math.min(math.max(2 - 4 * hue, 0), 1)),
         math.floor(255 * math.min(2 - math.abs(4 * hue - 2), 1)),
         math.floor(255 * math.min(math.max(4 * hue - 2, 0), 1))
end
local width = tty.getnum('cols')
for i = 1, width do
  local progress = (i - 1) / (width - 1)
  tty.set_foreground(hue_color(progress))
  tty.set_background(hue_color(1 - progress))
  tty.write('▄')
end
tty.set_foreground()
tty.set_background()

-- List the terminal's capabilities
local function fancy_write(value)
  if type(value) == 'table' then
    tty.write('{')
    for k, v in pairs(value) do
      fancy_write(k)
      tty.write(':')
      fancy_write(v)
      tty.write(',')
    end
    tty.write('}')
  elseif type(value) == 'string' then
    tty.write("'", value:gsub("'", "\\'"), "'")
  elseif value == true then
    tty.write('true')
  elseif value == false then
    tty.write('false')
  elseif value == nil then
    tty.write('nil')
  else
    tty.write(value)
  end
end
fancy_write(tty.cap)
tty.write('\r\n')

-- ANSI colors
for _, bg in ipairs(tty.ansi_colors) do
  tty.set_background(bg)
  for _, fg in ipairs(tty.ansi_colors) do
    tty.set_foreground(fg)
    tty.write('•')
  end
  tty.set_foreground()
  tty.set_background()
  tty.write(' ', bg, '\r\n')
end

-- Text style
tty.set_bold(true)
tty.write('bold')
tty.set_bold()
tty.write(' ')

tty.set_italic(true)
tty.write('italic')
tty.set_italic()
tty.write(' ')

tty.set_underline(true)
tty.write('un')
tty.set_underline_color('magenta')
tty.write('der')
tty.set_underline_color(255, 0, 191)
tty.write('line')
tty.set_underline()
tty.set_underline_color()
tty.write(' ')

tty.set_strikethrough(true)
tty.write('strikethrough')
tty.set_strikethrough()
tty.write(' ')

tty.set_hyperlink('https://example.com/')
tty.write('hyperlink')
tty.set_hyperlink()
tty.write(' ')

tty.write('\r\n')

-- Underline shapes
for _, name in pairs(tty.underline_shapes) do
  tty.set_underline_shape(name)
  tty.set_underline(true)
  tty.write(name)
  tty.set_underline()
  tty.write(' ')
end
tty.write('\r\n')

-- Mouse shapes part 1
tty.set_mouse_shape('wait')

-- ANSI-color window background
if tty.cap.window_background == 'true_color' or tty.cap.window_background == 'ansi' then
  for _, name in pairs(tty.ansi_colors) do
    tty.set_window_background(name)
    tty.flush()
    os.execute('sleep 0.4')
  end
  tty.set_window_background()
end

-- True-color window background
if tty.cap.window_background == 'true_color' then
  local start = os.clock()
  while true do
    local progress = (os.clock() - start) / 3
    if progress > 1 then break end
    tty.set_window_background(hue_color(progress))
    tty.flush()
  end
  tty.set_window_background()
end

-- Mouse shapes part 2
tty.set_mouse_shape('default')

-- Keyboard input, cursor shapes and window title
tty.set_cursor(true)
tty.write('Press ')
tty.set_italic(true)
tty.write('escape')
tty.set_italic()
tty.write(' to quit.\r\n')

for i = 1, math.huge do
  tty.read_events()
  local x = tty.input_buf
  if tty.input_buf == '\27' then break end
  x = x:gsub('\\', '\\\\')
  for i = 1, 31 do
    x = x:gsub(string.char(i), '\\' .. i)
  end
  tty.write(x)
  tty.input_buf = ''
  tty.set_cursor_shape(tty.cursor_shapes[i % #tty.cursor_shapes + 1])
  tty.set_window_title('The time is: ' .. os.date())
  tty.flush()
end

tty.restore()

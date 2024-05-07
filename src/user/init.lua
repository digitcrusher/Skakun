local tty = require('core.tty')

tty.setup()
tty.clear()

tty.goto(40, 5)
tty.set_foreground('black')
tty.set_background(255, 0, 191)
tty.write('czesc okej!!!')
tty.set_foreground()
tty.set_background()
tty.flush()
tty.goto(1, 1)

function fancy_write(value)
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

function hue_color(hue)
  return math.floor(255 * math.min(math.max(2 - 4 * hue, 0), 1)),
         math.floor(255 * math.min(2 - math.abs(4 * hue - 2), 1)),
         math.floor(255 * math.min(math.max(4 * hue - 2, 0), 1))
end
local width = require('core.terminfo').getnum('cols')
for i = 1, width do
  local progress = (i - 1) / (width - 1)
  tty.set_background(hue_color(progress))
  tty.set_foreground(hue_color(1 - progress))
  tty.write('▄')
end
tty.set_foreground()
tty.set_background()

function hello_world()
  tty.write('Hello, World! ')
  tty.set_italic(true)
  tty.write('Hello, World! ')
  tty.set_italic()
  tty.set_bold(true)
  tty.write('Hello, World! ')
  tty.set_italic(true)
  tty.write('Hello, World!\r\n')
  tty.set_bold()
  tty.set_italic()
end

tty.set_underline_color(255, 0, 191)
tty.set_underline_shape('curly')
hello_world()
tty.set_underline(true)
hello_world()
tty.set_underline()
tty.set_strikethrough(true)
hello_world()
tty.set_underline(true)
hello_world()
tty.set_underline()
tty.set_strikethrough()
tty.set_hyperlink('https://example.com/')
hello_world()
tty.set_underline(true)
hello_world()
tty.set_underline()
tty.set_strikethrough(true)
hello_world()
tty.set_underline(true)
hello_world()
tty.set_underline()
tty.set_strikethrough()
tty.set_hyperlink()

tty.set_mouse_shape('progress')

tty.write('Press ')
tty.set_italic(true)
tty.write('escape')
tty.set_italic()
tty.write(' to quit.\r\n')
while true do
  x = tty.read()
  if x == '' then
    tty.write('.')
  else
    tty.write((x:gsub('\\', '\\\\'):gsub('\27', '\\27')))
  end
  tty.flush()
  if x == '\27' then break end
end

tty.restore()

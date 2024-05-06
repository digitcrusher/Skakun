local tty = require('terminal')

tty.setup()

for _, bg in ipairs(tty.ansi_colors) do
  tty.set_background(bg)
  for _, fg in ipairs(tty.ansi_colors) do
    tty.set_foreground(fg)
    tty.write('•')
  end
  tty.set_background()
  tty.write(' ', bg, '\n')
end

function hello_world()
  tty.write('Hello, World! ')
  tty.set_italic(true)
  tty.write('Hello, World! ')
  tty.set_italic()
  tty.set_bold(true)
  tty.write('Hello, World! ')
  tty.set_italic(true)
  tty.write('Hello, World!\n')
  tty.set_bold()
  tty.set_italic()
end

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

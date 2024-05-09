--[[

We chose not to use any existing library, such as ncurses, because none of them
supports all the features of every terminal in existence and implementing
a custom, open solution in Lua gives the user more freedom in that and other
areas.

set_foreground(red, green, blue)
set_foreground(name)
  Sets the text foreground color. Red, green and blue must be in the range of
  0-255. Name must be one of ansi_colors or nil for the terminal default.

set_background(red, green, blue)
set_background(name)
  Sets the text background color. Red, green and blue must be in the range of
  0-255. Name must be one of ansi_colors or nil for the terminal default.


set_underline_color(red, green, blue)
set_underline_color(name)
  Sets the text underline color. Red, green and blue must be in the range of
  0-255. Name must be one of ansi_colors or nil for the terminal default.

set_hyperlink(url)
  Sets the URL that the text links to or, if url is nil, falls back to default
  terminal behavior of auto-detecting URLs.

set_mouse_shape(name)
  Sets the pointer shape for all areas of the terminal screen. Name must be one
  of mouse_shapes or nil for the terminal default.

]]--

local tty = {
  ansi_colors = {
    'black',
    'red',
    'green',
    'yellow',
    'blue',
    'magenta',
    'cyan',
    'white',
    'bright_black',
    'bright_red',
    'bright_green',
    'bright_yellow',
    'bright_blue',
    'bright_magenta',
    'bright_cyan',
    'bright_white',
  },

  underline_shapes = {
    'straight',
    'double',
    'curly',
    'dotted',
    'dashed',
  },

  cursor_shapes = {
    'block',
    'slab',
    'bar',
  },

  -- You can preview these here: https://developer.mozilla.org/en-US/docs/Web/CSS/cursor#keyword
  mouse_shapes = {
    'default', -- Note that this means the system default, not the terminal default.
    'none',
    'context_menu',
    'help',
    'pointer',
    'progress',
    'wait',
    'cell',
    'crosshair',
    'text',
    'vertical_text',
    'alias',
    'copy',
    'move',
    'no_drop',
    'not_allowed',
    'grab',
    'grabbing',
    'e_resize',
    'n_resize',
    'ne_resize',
    'nw_resize',
    's_resize',
    'se_resize',
    'sw_resize',
    'w_resize',
    'ew_resize',
    'ns_resize',
    'nesw_resize',
    'nwse_resize',
    'col_resize',
    'row_resize',
    'all_scroll',
    'zoom_in',
    'zoom_out',
  },

  -- Colors caps (foreground, background, underline_color and window_background)
  -- must be one of: 'true_color', 'ansi', false. Everything must be true or
  -- false.
  cap = {
    foreground = 'true_color',
    background = 'true_color',
    bold = true,
    italic = true,
    underline = true,
    underline_color = 'true_color',
    underline_shape = true,
    strikethrough = true,
    hyperlink = true,
    cursor = true,
    cursor_shape = true,
    mouse_shape = true,
    window_title = true,
    window_background = 'true_color',
  },

  state = {},
}

tty.write = io.write
tty.flush = io.flush
function tty.read(count)
  return io.read(count or '*a') or ''
end

local termios = require('core.termios')
local utils = require('core.utils')

function tty.setup()
  termios.enable_raw_mode()
  io.stdout:setvbuf('full') -- Cranks up boring line buffering to rad full buffering

  tty.detect_caps()
  tty.load_functions()
  tty.write('\27[?1049h') -- Switch to the alternate terminal screen
  tty.write('\27[?2004h') -- Enable bracketed paste
  tty.write('\27]22;>default\27\\', '\27]22;\27\\') -- Push the terminal default onto the pointer shape stack
end

function tty.restore()
  tty.reset() -- TODO: save the text attributes from before
  tty.write('\27[?1049l') -- Switch back to the primary terminal screen
  tty.write('\27[?2004l') -- Disable bracketed paste
  tty.write('\27]22;<\27\\') -- Pop our pointer shape from the stack

  io.stdout:setvbuf('line') -- And back to lame line buffering again…
  termios.disable_raw_mode()
end

function tty.detect_caps()
  -- kitty's terminfo was used as a reference of the available capnames:
  -- https://github.com/kovidgoyal/kitty/blob/master/kitty/terminfo.py
  -- VTE's commit history: https://gitlab.gnome.org/GNOME/vte/-/commits/master
  -- Konsole's commit history: https://invent.kde.org/utilities/konsole/-/commits/master
  -- xterm's changelog: https://invisible-island.net/xterm/xterm.log.html
  local vte = tonumber(os.getenv('VTE_VERSION')) or -1 -- VTE 0.34.5 (8bea17d1, 68046665)
  local konsole = tonumber(os.getenv('KONSOLE_VERSION')) or -1 -- Konsole 18.07.80 (b0d3d83e, 7e040b61)
  local xterm = os.getenv('XTERM_VERSION')
  if xterm then
    xterm = tonumber(xterm:match('%((%d+)%)'))
  else
    xterm = -1
  end

  -- The terminfo database has a reputation of not being the most reliable nor
  -- up-to-date and sadly there's no better, widespread way to query the
  -- terminal's capabilities. For example, on my Debian machine xterm sets $TERM
  -- to "xterm" instead of "xterm-256color" and that stops terminfo from knowing
  -- that xterm has the "initc" capability.
  local terminfo = require('core.terminfo')
  local getflag = terminfo.getflag
  local getnum = terminfo.getnum
  local getstr = terminfo.getstr

  -- This is an XTGETTCAP, which allows us to query the terminal's own terminfo
  -- entry. It's supported by… a *few* terminals. :/
  -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Device-Control-functions
  tty.read()
  tty.write('\27P+q', utils.hex_encode('cr'), '\27\\') -- An example query for "cr"
  tty.flush()
  if tty.read():match('^\27P[01]%+r.*\27\\$') then -- The terminal has replied with a well-formed answer.
    -- Flags don't work over XTGETTCAP, in kitty at least.
    function getnum(capname)
      tty.read()
      tty.write('\27P+q', utils.hex_encode(capname), '\27\\')
      tty.flush()
      local result = tty.read():match('^\27P1%+r.*=(%x*)\27\\$')
      if result then
        result = tonumber(utils.hex_decode(result))
      end
      return result
    end

    function getstr(capname)
      tty.read()
      tty.write('\27P+q', utils.hex_encode(capname), '\27\\')
      tty.flush()
      local result = tty.read():match('^\27P1%+r.*=(%x*)\27\\$')
      if result then
        result = utils.hex_decode(result)
      end
      return result
    end
  end

  -- VTE 0.35.1 (c5a32b49), Konsole 3.5.4 (f34d8203)
  -- It would probably be better to follow: https://github.com/termstandard/colors#querying-the-terminal
  -- We could also assume that 256-color terminals are always true-color:
  -- getflag('initc') or os.getenv('TERM'):find('256color')
  if vte >= 3501 or konsole >= 030504 or xterm >= 331 or getflag('Tc') or os.getenv('COLORTERM') == 'truecolor' or os.getenv('COLORTERM') == '24bit' then
    tty.cap.foreground = 'true_color'
    tty.cap.background = 'true_color'
  elseif getnum('colors') >= 8 then
    tty.cap.foreground = 'ansi'
    tty.cap.background = 'ansi'
  else
    tty.cap.foreground = false
    tty.cap.background = false
  end

  -- The Linux console interprets "bold" in its own way.
  if vte >= 0 or konsole >= 0 or xterm >= 0 or os.getenv('TERM') ~= 'linux' and getstr('bold') then
    tty.cap.bold = true
  else
    tty.cap.bold = false
  end

  -- VTE 0.34.1 (ad68297c), Konsole 4.10.80 (68a98ed7)
  if vte >= 3401 or konsole >= 041080 or xterm >= 305 or getstr('sitm') and getstr('ritm') then
    tty.cap.italic = true
  else
    tty.cap.italic = false
  end

  -- Konsole 0.8.44 (https://invent.kde.org/utilities/konsole/-/blob/d8f74118/ChangeLog#L99)
  if vte >= 0 or konsole >= 000844 or xterm >= 0 or os.getenv('TERM') ~= 'linux' and getstr('smul') and getstr('rmul') then
    tty.cap.underline = true
  else
    tty.cap.underline = false
  end

  -- VTE 0.51.2 - color, double, curly (efaf8f3c, a8af47bc); VTE 0.75.90 - dotted, dashed (bec7e6a2); Konsole 22.11.80 (76f879cd)
  -- Smulx does not necessarily indicate color support.
  if vte >= 5102 or konsole >= 221180 or getflag('Su') or getstr('Setulc') or getstr('Smulx') then
    tty.cap.underline_color = 'true_color'
    tty.cap.underline_shape = true
  else
    tty.cap.underline_color = false
    tty.cap.underline_shape = false
  end

  -- VTE 0.10.2 (a175a436), Konsole 16.07.80 (84b43dfb)
  if vte >= 1002 or konsole >= 160780 or xterm >= 305 or getstr('smxx') and getstr('rmxx') then
    tty.cap.strikethrough = true
  else
    tty.cap.strikethrough = false
  end

  -- VTE 0.49.1 (c9e7cbab), Konsole 20.11.80 (faceafcc)
  -- There is currently no universal way nor terminfo cap to detect hyperlink
  -- support. Further reading: https://github.com/kovidgoyal/kitty/issues/68
  tty.cap.hyperlink = vte >= 4901 or konsole >= 201180 or true

  -- VTE 0.1.0 (81af00a6), Konsole 0.8.42 (https://invent.kde.org/utilities/konsole/-/blob/d8f74118/ChangeLog#L107)
  if vte >= 0100 or konsole >= 000842 or xterm >= 0 or getstr('civis') and getstr('cnorm') then
    tty.cap.cursor = true
  else
    tty.cap.cursor = false
  end

  -- VTE 0.39.0 (430965a0); Konsole 18.07.80 (7c2a1164); xterm 252 - block, slab; xterm 282 - bar
  if vte >= 3900 or konsole >= 180780 or xterm >= 282 or getstr('Ss') and getstr('Se') then
    tty.cap.cursor_shape = true
  else
    tty.cap.cursor_shape = false
  end

  -- Reference: https://sw.kovidgoyal.net/kitty/pointer-shapes/#querying-support
  tty.read()
  tty.write('\27]22;?__current__\27\\')
  tty.flush()
  -- Kitty sends out a colon, even though its own docs say there should be
  -- a semicolon there???
  if tty.read():match('^\27]22:.*\27\\$') then
    tty.cap.mouse_shape = true
  else
    tty.cap.mouse_shape = false
  end

  -- VTE 0.10.14 (38fb4802, f39e2815)
  if vte >= 1014 or xterm >= 0 or getstr('tsl') and getstr('fsl') and getstr('dsl') then
    tty.cap.window_title = true
  else
    tty.cap.window_title = false
  end

  -- VTE 0.35.2 (1b8c6b1a), Konsole 3.3.0 (c20973ec)
  -- This does not appear to have its own terminfo cap.
  if vte >= 3502 or konsole >= 030300 or xterm >= 0 then
    tty.cap.window_background = 'true_color'
  else
    -- …But we can ask the terminal to send us the current background color and
    -- see if it understands us.
    -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
    tty.read()
    tty.write('\27]11;?\27\\')
    tty.flush()
    -- Konsole and st send BEL instead of ST at the end for some reason.
    if tty.read():match('^\27]11;(.*)\27?\\?\7?$') then
      tty.cap.window_background = 'true_color'
    else
      tty.cap.window_background = false
    end
  end

  -- Further reading: https://no-color.org/
  if os.getenv('NO_COLOR') and os.getenv('NO_COLOR') ~= '' then
    tty.cap.foreground = false
    tty.cap.background = false
    tty.cap.underline_color = false
    tty.cap.window_background = false
  end
end

-- Moves the cursor to the given position on the screen indexed from 1.
function tty.goto(x, y)
  tty.write('\27[', y, ';', x, 'H')
end

-- Clears the screen.
function tty.clear()
  tty.write('\27[2J')
end

-- Resets all text attributes to default.
function tty.reset()
  tty.write('\27[0m')
  tty.set_hyperlink()
  tty.state = {}
end

-- Loads all the functions whose values depend on the terminal's capabilities.
function tty.load_functions()
  -- Escape sequence reference: https://wezfurlong.org/wezterm/escape-sequences.html
  -- Further reading: https://gpanders.com/blog/state-of-the-terminal/
  -- Terminals ignore unknown OSC sequences, so stubs for them improve
  -- performance only.

  local ansi_color_fg_codes = {
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    bright_black = 90,
    bright_red = 91,
    bright_green = 92,
    bright_yellow = 93,
    bright_blue = 94,
    bright_magenta = 95,
    bright_cyan = 96,
    bright_white = 97,
  }
  if tty.cap.foreground == 'true_color' then
    function tty.set_foreground(red, green, blue)
      if blue then
        -- Reference: https://github.com/termstandard/colors
        -- According to the standards, the following syntax should use colons
        -- instead of semicolons but unfortunately the latter has become the
        -- predominant method due to misunderstandings and the passage of time.
        -- Further reading: https://chadaustin.me/2024/01/truecolor-terminal-emacs/
        tty.write('\27[38;2;', red, ';', green, ';', blue, 'm')
      elseif red then
        tty.write('\27[', ansi_color_fg_codes[red], 'm')
      else
        tty.write('\27[39m')
      end
    end
  elseif tty.cap.foreground == 'ansi' then
    function tty.set_foreground(red, green, blue)
      if red and not blue then
        -- The \27[22m here is important because in the Linux console the codes
        -- for the non-bright colors do not reset the brightness turned on by
        -- the bright colors.
        tty.write('\27[22;', ansi_color_fg_codes[red], 'm')
      else
        -- The above also applies to setting the default foreground color.
        tty.write('\27[22;39m')
      end
    end
  else
    -- I have yet to see a terminal in the 21st century that does not support
    -- any kind of text coloring.
    function tty.set_foreground() end
  end

  local ansi_color_bg_codes = {
    black = 40,
    red = 41,
    green = 42,
    yellow = 43,
    blue = 44,
    magenta = 45,
    cyan = 46,
    white = 47,
    bright_black = 100,
    bright_red = 101,
    bright_green = 102,
    bright_yellow = 103,
    bright_blue = 104,
    bright_magenta = 105,
    bright_cyan = 106,
    bright_white = 107,
  }
  if tty.cap.background == 'true_color' then
    function tty.set_background(red, green, blue)
      if blue then
        -- Reference: https://github.com/termstandard/colors
        -- Same story with semicolons vs colons as before.
        tty.write('\27[48;2;', red, ';', green, ';', blue, 'm')
      elseif red then
        tty.write('\27[', ansi_color_bg_codes[red], 'm')
      else
        tty.write('\27[49m')
      end
    end
  elseif tty.cap.background == 'ansi' then
    function tty.set_background(red, green, blue)
      if red and not blue then
        -- The bright colors don't work for the background in the Linux console.
        tty.write('\27[', ansi_color_bg_codes[red], 'm')
      else
        tty.write('\27[49m')
      end
    end
  else
    function tty.set_background() end
  end

  if tty.cap.bold then
    function tty.set_bold(is_enabled)
      if is_enabled then
        tty.write('\27[1m')
      else
        tty.write('\27[22m')
      end
      tty.state.bold = is_enabled
    end
  else
    -- Terminals without support simulate bold text by altering the foreground
    -- color, so it's important that we disable them.
    function tty.set_bold() end
  end

  if tty.cap.italic then
    -- Italics and boldness are mutually exclusive on xterm with italics taking
    -- precedence.
    function tty.set_italic(is_enabled)
      if is_enabled then
        tty.write('\27[3m')
      else
        tty.write('\27[23m')
      end
      tty.state.italic = is_enabled
    end
  else
    -- Terminals without support simulate italic text by altering the foreground
    -- color, so it's important that we disable them.
    function tty.set_italic() end
  end

  if tty.cap.underline then
    function tty.set_underline(is_enabled)
      -- Reference: https://sw.kovidgoyal.net/kitty/underlines/
      if is_enabled then
        if tty.state.underline_shape then
          local underline_shape_codes = {
            straight = 1,
            double = 2,
            curly = 3,
            dotted = 4,
            dashed = 5,
          }
          tty.write('\27[4:', underline_shape_codes[tty.state.underline_shape], 'm')
        else
          tty.write('\27[4m')
        end
      else
        tty.write('\27[24m')
      end
      tty.state.underline = is_enabled
    end
  else
    -- Terminals without support simulate underlined text by altering the
    -- foreground color, so it's important that we disable them.
    function tty.set_underline() end
  end

  if tty.cap.underline_color == 'true_color' then
    function tty.set_underline_color(red, green, blue)
      -- Reference: https://sw.kovidgoyal.net/kitty/underlines/
      if blue then
        -- Same semicolon story as with foreground and background.
        tty.write('\27[58;2;', red, ';', green, ';', blue, 'm')
      elseif red then
        -- Sadly, there appears to be no escape sequence for ANSI underline
        -- colors. We have to fetch the RGB value from the terminal.
        -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
        local ansi_color_codes = {
          black = 0,
          red = 1,
          green = 2,
          yellow = 3,
          blue = 4,
          magenta = 5,
          cyan = 6,
          white = 7,
          bright_black = 8,
          bright_red = 9,
          bright_green = 10,
          bright_yellow = 11,
          bright_blue = 12,
          bright_magenta = 13,
          bright_cyan = 14,
          bright_white = 15,
        }
        tty.read()
        tty.write('\27]4;', ansi_color_codes[red], ';?\27\\')
        tty.flush()
        -- Konsole and st send BEL instead of ST at the end for some reason.
        -- Fun fact: We can and may send RGB colors to the terminal in two
        -- different formats (#RRGGBB and rgb:RR/GG/BB) as part of the various
        -- sequences originating from xterm, but why do terminals always have to
        -- send back the second one? Well, xterm uses XParseColor for parsing
        -- our colors and it turns out that the former format (or in the words
        -- of X11 itself: "RGB Device") is actually deprecated by XParseColor!
        -- Source: man 3 XParseColor
        local red, green, blue = tty.read():match('^\27]4;%d*;rgb:(%x%x)%x*/(%x%x)%x*/(%x%x)%x*\27?\\?\7?$')
        tty.set_underline_color(tonumber(red, 16), tonumber(green, 16), tonumber(blue, 16))
      else
        tty.write('\27[59m')
      end
    end
  else
    function tty.set_underline_color() end
  end

  -- Name must be one of underline_shapes or nil for the terminal default.
  if tty.cap.underline_shape then
    function tty.set_underline_shape(name)
      tty.state.underline_shape = name
      tty.set_underline(tty.state.underline)
    end
  else
    -- Underline shapes turn the text black on xterm, so it's important that we
    -- disable them.
    function tty.set_underline_shape() end
  end

  if tty.cap.strikethrough then
    function tty.set_strikethrough(is_enabled)
      if is_enabled then
        tty.write('\27[9m')
      else
        tty.write('\27[29m')
      end
      tty.state.strikethrough = is_enabled
    end
  else
    function tty.set_strikethrough() end
  end

  if tty.cap.hyperlink then
    function tty.set_hyperlink(url)
      -- Reference: https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda
      if url then
        -- ESCs and all other ASCII control characters are disallowed in valid URLs
        -- anyways. According to the specification in the link above we should also
        -- percent-encode all bytes outside of the 32-126 range but who cares?
        -- *It works on my machine.* ¯\_(ツ)_/¯
        tty.write('\27]8;;', url:gsub('\27', '%%1b'), '\27\\')
      else
        tty.write('\27]8;;\27\\')
      end
    end
  else
    function tty.set_hyperlink() end
  end

  if tty.cap.cursor then
    function tty.set_cursor(is_visible)
      if is_visible == true or is_visible == nil then -- A visible cursor should be the default.
        tty.write('\27[?25h')
      else
        tty.write('\27[?25l')
      end
    end
  else
    function tty.set_cursor() end
  end

  if tty.cap.cursor_shape then
    if os.getenv('TERM') == 'linux' then
      function tty.set_cursor_shape(name)
        -- Reference: https://www.kernel.org/doc/html/latest/admin-guide/vga-softcursor.html
        if name == 'block' then
          tty.write('\27[?8c')
        elseif name == 'slab' then
          tty.write('\27[?2c')
        else
          tty.write('\27[?0c')
        end
      end
    else
      function tty.set_cursor_shape(name)
        -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Functions-using-CSI-_-ordered-by-the-final-character_s_
        if name == 'block' then
          tty.write('\27[1 q')
        elseif name == 'slab' then
          tty.write('\27[3 q')
        elseif name == 'bar' then
          tty.write('\27[5 q')
        else
          tty.write('\27[ q')
        end
      end
    end
  else
    function tty.set_cursor_shape() end
  end

  if tty.cap.mouse_shape then
    function tty.set_mouse_shape(name)
      -- Reference: https://sw.kovidgoyal.net/kitty/pointer-shapes/
      -- The CSS names have hyphens, not underscores.
      tty.write('\27]22;', (name or ''):gsub('_', '-'), '\27\\')
      -- They don't work on xterm by the way, which has its own set of pointer
      -- shape names: https://invisible-island.net/xterm/manpage/xterm.html#VT100-Widget-Resources:pointerShape
    end
  else
    function tty.set_mouse_shape() end
  end

  if tty.cap.window_title then
    function tty.set_window_title(string)
      -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
      if string == '' then
        tty.write('\27]2; \27\\') -- Because '' should make the title empty, and not set it to terminal default.
      else
        tty.write('\27]2;', (string or ''):gsub('\27', ''), '\27\\')
      end
    end
  else
    function tty.set_window_title() end
  end

  if tty.cap.window_background then
    function tty.set_window_background(red, green, blue)
      -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
      if blue then
        -- I don't know why but this is ridiculously slow on kitty and st.
        -- Fun fact: xterm-compatibles accept X11 color names here, which you
        -- can find in /etc/X11/rgb.txt.
        tty.write(string.format('\27]11;#%02x%02x%02x\27\\', red, green, blue))
      elseif red then
        -- We have to fetch the ANSI color's RGB value from the terminal because
        -- there's no other way.
        local ansi_color_codes = {
          black = 0,
          red = 1,
          green = 2,
          yellow = 3,
          blue = 4,
          magenta = 5,
          cyan = 6,
          white = 7,
          bright_black = 8,
          bright_red = 9,
          bright_green = 10,
          bright_yellow = 11,
          bright_blue = 12,
          bright_magenta = 13,
          bright_cyan = 14,
          bright_white = 15,
        }
        tty.read()
        tty.write('\27]4;', ansi_color_codes[red], ';?\27\\')
        tty.flush()
        -- Konsole and st send BEL instead of ST at the end for some reason.
        tty.write('\27]11;', tty.read():match('^\27]4;%d*;(.*)\27?\\?\7?$'), '\27\\')
      else
        tty.write('\27]111;\27\\')
      end
    end
  else
    function tty.set_window_background() end
  end
end

return tty

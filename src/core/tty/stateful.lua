-- Skakun - A robust and hackable hex and text editor
-- Copyright (C) 2024 Karol "digitcrusher" Łacina
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

local core = require('core')
local InputParser = require('core.tty.input_parser')
local unix
if core.platform == 'linux' then
  unix = require('core.tty.linux')
elseif core.platform == 'freebsd' then
  unix = require('core.tty.freebsd')
end
local system = require('core.tty.system')
local utils = require('core.utils')
local windows
if core.platform == 'windows' then
  windows = require('core.tty.windows')
end

local tty = setmetatable({
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
    'straight', -- ─────
    'double',   -- ═════
    'curly',    -- ﹏﹏﹏
    'dotted',   -- ┈┈┈┈┈
    'dashed',   -- ╌╌╌╌╌
  },

  cursor_shapes = {
    'block', -- █
    'slab',  -- ▁
    'bar',   -- ▎
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
    'e_resize',    -- →
    'n_resize',    -- ↑
    'ne_resize',   -- ↗
    'nw_resize',   -- ↖
    's_resize',    -- ↓
    'se_resize',   -- ↘
    'sw_resize',   -- ↙
    'w_resize',    -- ←
    'ew_resize',   -- ↔
    'ns_resize',   -- ↕
    'nesw_resize', -- ⤢
    'nwse_resize', -- ⤡
    'col_resize',
    'row_resize',
    'all_scroll',
    'zoom_in',
    'zoom_out',
  },

  -- All of the 104 keys of a standard US layout Windows keyboard
  buttons = {
    'escape', 'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11', 'f12', 'print_screen', 'scroll_lock', 'pause',
    'backtick', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'minus', 'equal', 'backspace',
    'tab', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', 'left_bracket', 'right_bracket', 'backslash',
    'caps_lock', 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'semicolon', 'apostrophe', 'enter',
    'left_shift', 'z', 'x', 'c', 'v', 'b', 'n', 'm', 'comma', 'dot', 'slash', 'right_shift',
    'left_ctrl', 'left_super', 'left_alt', 'space', 'right_alt', 'right_super', 'menu', 'right_ctrl',
    'insert', 'delete', 'home', 'end', 'page_up', 'page_down',
    'up', 'left', 'down', 'right',
    'num_lock', 'kp_divide', 'kp_multiply', 'kp_subtract', 'kp_add', 'kp_enter', 'kp_1', 'kp_2', 'kp_3', 'kp_4', 'kp_5', 'kp_6', 'kp_7', 'kp_8', 'kp_9', 'kp_0', 'kp_decimal',
    'mouse_left', 'mouse_middle', 'mouse_right', 'scroll_up', 'scroll_down', 'scroll_left', 'scroll_right', 'mouse_prev', 'mouse_next',
  },

  -- Reminder: color caps must be one of: 'true_color', 'ansi', false.
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
    clipboard = 'remote', -- Must be one of: 'remote', 'local', false.
  },

  state = {},
}, { __index = system })

function tty.setup()
  tty.open()
  if unix then
    local ok
    ok, tty.input_parser = pcall(unix.Kbd.new)
    if ok then
      unix.enable_raw_kbd()
    else
      tty.input_parser = InputParser.new()
    end
  else
    tty.input_parser = InputParser.new()
  end
  tty.enable_raw_mode()
  tty.detect_caps()
  tty.load_functions()
  tty.write('\27[?1049h') -- Switch to the alternate terminal screen
  tty.write('\27[?2004h') -- Enable bracketed paste
  tty.write('\27[>31u') -- Send key events in Kitty's format
  tty.write('\27=') -- Discriminate numpad keys
  tty.write('\27[?1000h') -- Enable mouse button events
  tty.write('\27[?1003h') -- Enable mouse movement events
  tty.write('\27[?1006h') -- Extend the range of mouse coordinates the terminal is able to report
  tty.write('\27]22;>default\27\\', '\27]22;\27\\') -- Push the terminal default onto the pointer shape stack
  tty.write('\27[22;0t') -- Save the window title on the stack
end

function tty.restore()
  tty.write('\27[0m')
  tty.write('\27[23;0t') -- Restore the window title from the stack
  tty.write('\27]22;<\27\\') -- Pop our pointer shape from the stack
  tty.write('\27[?1006l') -- Shrink the range of mouse coordinates to default
  tty.write('\27[?1003l') -- Disable mouse movement events
  tty.write('\27[?1000l') -- Disable mouse button events
  tty.write('\27>') -- Don't discriminate numpad keys
  tty.write('\27[<u') -- Pop the Kitty key event format from the stack
  tty.write('\27[?2004l') -- Disable bracketed paste
  tty.write('\27[?1049l') -- Switch back to the primary terminal screen
  tty.disable_raw_mode()
  if unix then
    pcall(unix.disable_raw_kbd)
  end
  tty.close()
end

function tty.detect_caps()
  -- kitty's terminfo was used as a reference of the available capnames:
  -- https://github.com/kovidgoyal/kitty/blob/master/kitty/terminfo.py
  -- VTE's commit history: https://gitlab.gnome.org/GNOME/vte/-/commits/master
  -- Konsole's commit history: https://invent.kde.org/utilities/konsole/-/commits/master
  -- …which, geez, a pain to follow it was.
  -- xterm's changelog: https://invisible-island.net/xterm/xterm.log.html
  local vte = tonumber(os.getenv('VTE_VERSION')) or -1 -- VTE 0.34.5 (8bea17d1, 68046665)
  local konsole = tonumber(os.getenv('KONSOLE_VERSION')) or -1 -- Konsole 18.07.80 (b0d3d83e, 7e040b61)
  local xterm = os.getenv('XTERM_VERSION')
  if xterm then
    xterm = tonumber(xterm:match('%((%d+)%)'))
  else
    xterm = -1
  end

  -- This is an XTGETTCAP, which allows us to forget about the unreliable
  -- system-wide database and query the terminal's own terminfo entry. It's
  -- supported by… a *few* terminals. :/
  -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Device-Control-functions
  tty.write('\27P+q', utils.hex_encode('cr'), '\27\\') -- An example query for "cr"
  tty.read_events()
  tty.flush()
  if tty.read():match('^\27P[01]%+r.*\27\\$') then -- The terminal has replied with a well-formed answer.
    -- Flags don't work over XTGETTCAP, in kitty at least.
    function tty.getnum(capname, term)
      if term ~= nil then
        return system.getnum(capname, term)
      end

      tty.write('\27P+q', utils.hex_encode(capname), '\27\\')
      tty.read_events()
      tty.flush()
      local result = tty.read():match('^\27P1%+r.*=(%x*)\27\\$')
      if result then
        result = tonumber(utils.hex_decode(result))
      end
      return result
    end

    function tty.getstr(capname, term)
      if term ~= nil then
        return system.getstr(capname, term)
      end

      tty.write('\27P+q', utils.hex_encode(capname), '\27\\')
      tty.read_events()
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
  -- tty.getflag('initc') or os.getenv('TERM'):find('256color')
  if vte >= 3501 or konsole >= 030504 or xterm >= 331 or tty.getflag('Tc') or os.getenv('COLORTERM') == 'truecolor' or os.getenv('COLORTERM') == '24bit' then
    tty.cap.foreground = 'true_color'
    tty.cap.background = 'true_color'
  elseif tty.getnum('colors') >= 8 then
    tty.cap.foreground = 'ansi'
    tty.cap.background = 'ansi'
  else
    -- I have yet to see a terminal in the 21st century that does not support
    -- any kind of text coloring.
    tty.cap.foreground = false
    tty.cap.background = false
  end

  -- The Linux console interprets "bold" in its own way.
  if vte >= 0 or konsole >= 0 or xterm >= 0 or os.getenv('TERM') ~= 'linux' and tty.getstr('bold') then
    tty.cap.bold = true
  else
    tty.cap.bold = false
  end

  -- VTE 0.34.1 (ad68297c), Konsole 4.10.80 (68a98ed7)
  if vte >= 3401 or konsole >= 041080 or xterm >= 305 or tty.getstr('sitm') and tty.getstr('ritm') then
    tty.cap.italic = true
  else
    tty.cap.italic = false
  end

  -- Konsole 0.8.44 (https://invent.kde.org/utilities/konsole/-/blob/d8f74118/ChangeLog#L99)
  if vte >= 0 or konsole >= 000844 or xterm >= 0 or os.getenv('TERM') ~= 'linux' and tty.getstr('smul') and tty.getstr('rmul') then
    tty.cap.underline = true
  else
    tty.cap.underline = false
  end

  -- VTE 0.51.2 - color, double, curly (efaf8f3c, a8af47bc); VTE 0.75.90 - dotted, dashed (bec7e6a2); Konsole 22.11.80 (76f879cd)
  -- Smulx does not necessarily indicate color support.
  if vte >= 5102 or konsole >= 221180 or tty.getflag('Su') or tty.getstr('Setulc') or tty.getstr('Smulx') then
    tty.cap.underline_color = 'true_color'
    tty.cap.underline_shape = true
  else
    tty.cap.underline_color = false
    tty.cap.underline_shape = false
  end

  -- VTE 0.10.2 (a175a436), Konsole 16.07.80 (84b43dfb)
  if vte >= 1002 or konsole >= 160780 or xterm >= 305 or tty.getstr('smxx') and tty.getstr('rmxx') then
    tty.cap.strikethrough = true
  else
    tty.cap.strikethrough = false
  end

  -- VTE 0.49.1 (c9e7cbab), Konsole 20.11.80 (faceafcc)
  -- There is currently no universal way to detect hyperlink support.
  -- Further reading: https://github.com/kovidgoyal/kitty/issues/68
  tty.cap.hyperlink = vte >= 4901 or konsole >= 201180 or true

  -- VTE 0.1.0 (81af00a6), Konsole 0.8.42 (https://invent.kde.org/utilities/konsole/-/blob/d8f74118/ChangeLog#L107)
  if vte >= 0100 or konsole >= 000842 or xterm >= 0 or tty.getstr('civis') and tty.getstr('cnorm') then
    tty.cap.cursor = true
  else
    tty.cap.cursor = false
  end

  -- VTE 0.39.0 (430965a0); Konsole 18.07.80 (7c2a1164); xterm 252 - block, slab; xterm 282 - bar
  if vte >= 3900 or konsole >= 180780 or xterm >= 282 or tty.getstr('Ss') and tty.getstr('Se') then
    tty.cap.cursor_shape = true
  else
    tty.cap.cursor_shape = false
  end

  -- Reference: https://sw.kovidgoyal.net/kitty/pointer-shapes/#querying-support
  tty.write('\27]22;?__current__\27\\')
  tty.read_events()
  tty.flush()
  -- Kitty sends out a colon, even though its own docs say there should be
  -- a semicolon there???
  if tty.read():match('^\27]22:.*\27\\$') then
    tty.cap.mouse_shape = true
  else
    tty.cap.mouse_shape = false
  end

  -- VTE 0.10.14 (38fb4802, f39e2815)
  if vte >= 1014 or xterm >= 0 or tty.getstr('tsl') and tty.getstr('fsl') and tty.getstr('dsl') then
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
    tty.write('\27]11;?\27\\')
    tty.read_events()
    tty.flush()
    -- Konsole and st send BEL instead of ST at the end for some reason.
    if tty.read():match('^\27]11;(.*)\27?\\?\7?$') then
      tty.cap.window_background = 'true_color'
    else
      tty.cap.window_background = false
    end
  end

  -- You may have to explicitly enable this: https://github.com/tmux/tmux/wiki/Clipboard
  if xterm >= 238 or tty.getstr('Ms') then
    tty.cap.clipboard = 'remote'
  else
    tty.cap.clipboard = 'local'
  end

  -- Further reading: https://no-color.org/
  if os.getenv('NO_COLOR') and os.getenv('NO_COLOR') ~= '' then
    tty.cap.foreground = false
    tty.cap.background = false
    tty.cap.underline_color = false
    tty.cap.window_background = false
  end
end

function tty.sync_begin()
  tty.write('\27[?2026h')
end

function tty.sync_end()
  tty.write('\27[?2026l')
end

function tty.clear()
  tty.write('\27[2J')
end

function tty.reset()
  tty.write('\27[0m')
  tty.set_hyperlink()
  tty.set_cursor()
  tty.set_cursor_shape()
  tty.set_window_background()
  tty.state = {}
end

function tty.move_to(x, y)
  if x and y then
    tty.write('\27[', y, ';', x, 'H')
  elseif x then
    tty.write('\27[', x, 'G')
  elseif y then
    tty.write('\27[', y, 'd')
  end
end

function tty.load_functions()
  -- Escape sequence references:
  -- - man 4 console_codes
  -- - https://wezfurlong.org/wezterm/escape-sequences.html
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
        tty.state.foreground = { red = red, green = green, blue = blue }
      elseif red then
        tty.write('\27[', ansi_color_fg_codes[red], 'm')
        tty.state.foreground = red
      else
        tty.write('\27[39m')
        tty.state.foreground = nil
      end
    end
  elseif tty.cap.foreground == 'ansi' then
    function tty.set_foreground(red, green, blue)
      if red and not blue then
        -- The \27[22m here is important because in the Linux console the codes
        -- for the non-bright colors do not reset the brightness turned on by
        -- the bright colors.
        tty.write('\27[22;', ansi_color_fg_codes[red], 'm')
        tty.state.foreground = red
      else
        -- The above also applies to setting the default foreground color.
        tty.write('\27[22;39m')
        tty.state.foreground = nil
      end
    end
  else
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
        tty.state.background = { red = red, green = green, blue = blue }
      elseif red then
        tty.write('\27[', ansi_color_bg_codes[red], 'm')
        tty.state.background = red
      else
        tty.write('\27[49m')
        tty.state.background = nil
      end
    end
  elseif tty.cap.background == 'ansi' then
    function tty.set_background(red, green, blue)
      if red and not blue then
        -- The bright colors don't work for the background in the Linux console.
        tty.write('\27[', ansi_color_bg_codes[red], 'm')
        tty.state.background = red
      else
        tty.write('\27[49m')
        tty.state.background = nil
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
        tty.state.underline_color = { red = red, green = green, blue = blue }
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
        tty.write('\27]4;', ansi_color_codes[red], ';?\27\\')
        tty.read_events()
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
        tty.state.underline_color = red
      else
        tty.write('\27[59m')
        tty.state.underline_color = nil
      end
    end
  else
    function tty.set_underline_color() end
  end

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
      -- ESCs and all other ASCII control characters are disallowed in valid URLs
      -- anyways. According to the specification in the link above we should also
      -- percent-encode all bytes outside of the 32-126 range but who cares?
      -- *It works on my machine.* ¯\_(ツ)_/¯
      tty.write('\27]8;;', (url or ''):gsub('\27', '%%1b'), '\27\\')
      tty.state.url = url
    end
  else
    function tty.set_hyperlink() end
  end

  if tty.cap.cursor then
    function tty.set_cursor(is_visible)
      -- There's no "reset cursor visibility to default" code, unless we query
      -- terminfo for "cnorm".
      if is_visible == true or is_visible == nil then
        tty.write('\27[?25h')
      else
        tty.write('\27[?25l')
      end
      tty.state.cursor = is_visible
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
          -- No bar cursor available, sorry :(
        else
          tty.write('\27[?0c')
        end
        tty.state.cursor_shape = name
      end
    else
      function tty.set_cursor_shape(name)
        -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Functions-using-CSI-_-ordered-by-the-final-character_s_
        -- This utilizes only the blinking versions of the cursor shapes.
        if name == 'block' then
          tty.write('\27[1 q')
        elseif name == 'slab' then
          tty.write('\27[3 q')
        elseif name == 'bar' then
          tty.write('\27[5 q')
        else
          tty.write('\27[ q')
        end
        tty.state.cursor_shape = name
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
      tty.state.mouse_shape = name
    end
  else
    function tty.set_mouse_shape() end
  end

  if tty.cap.window_title then
    function tty.set_window_title(text)
      -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
      if text == '' then
        tty.write('\27]2; \27\\') -- Because '' should make the title empty, and not set it to terminal default.
      else
        tty.write('\27]2;', (text or ''):gsub('\27', ''), '\27\\')
      end
      tty.state.window_title = text
    end
  else
    function tty.set_window_title() end
  end

  if tty.cap.window_background then
    function tty.set_window_background(red, green, blue)
      -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
      if blue then
        -- I don't know why, but this is ridiculously slow on kitty and st.
        -- Fun fact: xterm-compatibles accept X11 color names here, which you
        -- can find in /etc/X11/rgb.txt.
        tty.write(string.format('\27]11;#%02x%02x%02x\27\\', red, green, blue))
        tty.state.window_background = { red = red, green = green, blue = blue }
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
        tty.write('\27]4;', ansi_color_codes[red], ';?\27\\')
        tty.read_events()
        tty.flush()
        -- Konsole and st send BEL instead of ST at the end for some reason.
        tty.write('\27]11;', tty.read():match('^\27]4;%d*;(.*)\27?\\?\7?$'), '\27\\')
        tty.state.window_background = red
      else
        tty.write('\27]111;\27\\')
        tty.state.window_background = nil
      end
    end
  else
    function tty.set_window_background() end
  end

  if tty.cap.clipboard == 'remote' then
    function tty.set_clipboard(text)
      -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
      tty.write('\27]52;c;', utils.base64_encode(text or ''), '\27\\')
    end
  elseif tty.cap.clipboard == 'local' then
    function tty.set_clipboard(text)
      if core.platform == 'windows' then
        windows.set_clipboard(text)
      elseif core.platform == 'macos' then
        pipe = io.popen('pbcopy', 'w')
        pipe:write(text or '')
        pipe:close()
      else
        -- io.popen fails silently when the program errors out or isn't
        -- available, so we just try all of them in sequence LOL.
        for _, cmd in ipairs({
          'xclip -selection clipboard',
          'xsel --clipboard',
          'wl-copy',
        }) do
          pipe = io.popen(cmd, 'w')
          pipe:write(text or '')
          pipe:close()
        end
      end
    end
  else
    function tty.set_clipboard() end
  end
end

function tty.read_events()
  local result = {}
  while true do
    local events = tty.input_parser:feed(tty.read())
    if #events == 0 then break end
    for _, event in ipairs(events) do
      result[#result + 1] = event
    end
  end
  return result
end

return tty

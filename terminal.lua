--[[

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

  -- foreground, background and underline_color must be one of: 'true_color', 'ansi', false
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
    mouse_shape = true,
  },

  state = {},

  write = io.write,
}


function tty.setup()
  tty.detect_caps()
  tty.load_functions()
  -- TODO: register atexit for tty.restore
  tty.write('\27[?1049h') -- Switches to the alternate terminal screen
end

local terminfo = require('terminfo')
function tty.detect_caps()
  -- The terminfo database has a reputation of not being the most reliable nor
  -- up-to-date and sadly there's no better standard way to query the terminal's
  -- capabilities.
end

function tty.restore()
  tty.reset()
  tty.write('\27[?1049l') -- Switches back to the primary terminal screen
end

-- Moves the cursor to the given position on the screen.
function tty.goto(x, y)
  tty.write('\27[', y + 1, ';', x + 1, 'H')
end

-- Clears the screen.
function tty.clear()
  tty.write('\27[2J')
end

-- Resets all text and terminal attributes to default.
function tty.reset()
  tty.write('\27[0m')
  tty.set_mouse_shape()
  tty.state = {}
end

-- Loads all the functions whose values depend on the terminal's capabilities.
function tty.load_functions()
  -- Further reading for all: https://gpanders.com/blog/state-of-the-terminal/

  local ansi_color_codes = {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    bright_black = 60,
    bright_red = 61,
    bright_green = 62,
    bright_yellow = 63,
    bright_blue = 64,
    bright_magenta = 65,
    bright_cyan = 66,
    bright_white = 67,
  }

  if tty.cap.foreground == 'true_color' then
    function tty.set_foreground(red, green, blue)
      if blue then
        -- According to the standards, the following syntax should use colons
        -- instead of semicolons but unfortunately the latter has become the
        -- predominant method due to misunderstandings and the passage of time.
        -- Further reading: https://chadaustin.me/2024/01/truecolor-terminal-emacs/
        tty.write('\27[38;2;', red, ';', green, ';', blue, 'm')
      elseif red then
        tty.write('\27[', ansi_color_codes[red] + 30, 'm')
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
        tty.write('\27[22;', ansi_color_codes[red] + 30, 'm')
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

  if tty.cap.background == 'true_color' then
    function tty.set_background(red, green, blue)
      if blue then
        -- Same story with semicolons vs colons as before.
        tty.write('\27[48;2;', red, ';', green, ';', blue, 'm')
      elseif red then
        tty.write('\27[', ansi_color_codes[red] + 40, 'm')
      else
        tty.write('\27[49m')
      end
    end
  elseif tty.cap.background == 'ansi' then
    function tty.set_background(red, green, blue)
      if red and not blue then
        -- The bright colors don't work for the background in the Linux console.
        tty.write('\27[', ansi_color_codes[red] + 40, 'm')
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
    end
  else
    -- Terminals without support simulate bold text by altering the foreground
    -- color, so it's important that we disable them.
    function tty.set_bold() end
  end

  if tty.cap.italic then
    -- Italics and boldness are mutually exclusive on xterm (as of version 379)
    -- with italics taking precedence.
    function tty.set_italic(is_enabled)
      if is_enabled then
        tty.write('\27[3m')
      else
        tty.write('\27[23m')
      end
    end
  else
    -- Terminals without support simulate italic text by altering the foreground
    -- color, so it's important that we disable them.
    function tty.set_italic() end
  end


  local underline_shape_codes = {
    straight = 1,
    double = 2,
    curly = 3,
    dotted = 4,
    dashed = 5,
  }

  if tty.cap.underline then
    -- Further reading: https://sw.kovidgoyal.net/kitty/underlines/<
    function tty.set_underline(is_enabled)
      tty.state.underline = is_enabled
      if is_enabled then
        if tty.state.underline_shape then
          tty.write('\27[4:', underline_shape_codes[tty.state.underline_shape], 'm')
        else
          tty.write('\27[4m')
        end
      else
        tty.write('\27[24m')
      end
    end
  else
    -- Terminals without support simulate underlined text by altering the
    -- foreground color, so it's important that we disable them.
    function tty.set_underline() end
  end

  if tty.cap.underline_color == 'true_color' then
    function tty.set_underline_color(red, green, blue)
      if blue then
        -- Same semicolon story as with foreground and background.
        tty.write('\27[58;2;', red, ';', green, ';', blue, 'm')
      else
        -- Sadly, there appears to be no escape sequence for ANSI underline colors.
        tty.write('\27[59m')
      end
    end
  else
    function tty.set_underline_color() end
  end

  -- Name must be one of underline_shapes or nil for the terminal default.
  function tty.set_underline_shape(name)
    tty.state.underline_shape = name
    tty.set_underline(tty.state.underline)
  end

  if tty.cap.strikethrough then
    function tty.set_strikethrough(is_enabled)
      tty.state.strikethrough = is_enabled
      if is_enabled then
        tty.write('\27[9m')
      else
        tty.write('\27[29m')
      end
    end
  else
    function tty.set_strikethrough() end
  end

  if tty.cap.hyperlink then
    -- There is currently no universal escape sequence nor
    -- terminfo entry to query whether the terminal supports this, but using this
    -- out in terminals without support doesn't have unintended side-effects.
    -- Further reading:
    -- https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda
    -- https://github.com/kovidgoyal/kitty/issues/68
    function tty.set_hyperlink(url)
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
    -- The escape sequence is designed not to have unintended side-effects in
    -- terminals that don't support it, so this stub improves performance only.
    function tty.set_hyperlink() end
  end

  if tty.cap.mouse_shape then
    -- Further reading: https://sw.kovidgoyal.net/kitty/pointer-shapes/
    function tty.set_mouse_shape(name)
      -- The CSS names have hyphens, not underscores.
      tty.write('\27]22;', (name or ''):gsub('_', '-'), '\27\\')
      -- They don't work on xterm by the way, which has its own set of pointer
      -- shape names:
      -- https://invisible-island.net/xterm/manpage/xterm.html#VT100-Widget-Resources:pointerShape
    end
  else
    -- The escape sequence is designed not to have unintended side-effects in
    -- terminals that don't support it, so this stub improves performance only.
    function tty.set_mouse_shape() end
  end
end

return tty

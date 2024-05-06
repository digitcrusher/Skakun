local tty = {}

tty.ansi_colors = {
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
}

-- set_foreground(red, green, blue)
-- set_foreground(ansi)
-- set_foreground()
-- Sets the text color to the given RGB. Red, green and blue must be in the range of 0-255. ansi must be one of colors in ansi_colors.
--
-- set_background(red, green, blue)
-- set_background(ansi)
-- set_background()

tty.write = io.write

tty.cap = {
  true_color = true,
  bold = true,
  italic = true,
  underline = true,
  strikethrough = true,
  hyperlink = true,
}

function tty.setup()
  tty.load_functions()
  -- TODO: register atexit for tty.restore
end

function tty.restore()
end

-- Loads all the functions whose values depend on the terminal's capabilities.
function tty.load_functions()
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

  if tty.cap.true_color then
    function tty.set_foreground(red, green, blue)
      if blue then
        tty.write('\27[38;2:', red, ':', green, ':', blue, 'm')
      elseif red then
        tty.write('\27[', ansi_color_codes[red] + 30, 'm')
      else
        tty.write('\27[39m')
      end
    end

    function tty.set_background(red, green, blue)
      if blue then
        tty.write('\27[48;2:', red, ':', green, ':', blue, 'm')
      elseif red then
        tty.write('\27[', ansi_color_codes[red] + 40, 'm')
      else
        tty.write('\27[49m')
      end
    end

  else
    function tty.set_foreground(red, green, blue)
      if red and not blue then
        -- The \27[22m here is important because the codes for the non-bright
        -- colors do not reset the brightness turned on by the bright colors.
        tty.write('\27[22;', ansi_color_codes[red] + 30, 'm')
      else
        tty.write('\27[39m')
      end
    end

    function tty.set_background(red, green, blue)
      if red and not blue then
        -- The bright colors don't work for the background.
        tty.write('\27[', ansi_color_codes[red] + 40, 'm')
      else
        tty.write('\27[49m')
      end
    end
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
    -- The above escape sequences brighten the foreground on terminals that
    -- don't support bold text, so it's important that we disable them.
    function tty.set_bold() end
  end

  if tty.cap.italic then
    -- Italics and boldness are mutually exclusive on xterm (as of version 379) with italics taking precedence.
    function tty.set_italic(is_enabled)
      if is_enabled then
        tty.write('\27[3m')
      else
        tty.write('\27[23m')
      end
    end
  else
    function tty.set_italic() end
  end

  if tty.cap.underline then
    function tty.set_underline(is_enabled)
      if is_enabled then
        tty.write('\27[4m')
      else
        tty.write('\27[24m')
      end
    end
  else
    function tty.set_underline() end
  end

  if tty.cap.strikethrough then
    function tty.set_strikethrough(is_enabled)
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
    -- Sets the clickable hyperlink that the text points to. Most terminals add
    -- some kind of underline to hyperlinked text. There is currently no universal escape sequence nor
    -- terminfo entry to query whether the terminal supports this, but using this
    -- out in terminals without support doesn't have unintended side-effects.
    -- Further reading:
    -- - https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda
    -- - https://github.com/kovidgoyal/kitty/issues/68
    function tty.set_hyperlink(value)
      if value then
        -- ESCs and all other ASCII control characters are disallowed in valid URLs
        -- anyways. According to the specification in the link above we should also
        -- percent-encode all bytes outside of the 32-126 range but who cares?
        -- *It works on my machine.* ¯\_(ツ)_/¯
        tty.write('\27]8;;', value:gsub('\27', '%%1b'), '\27\\')
      else
        tty.write('\27]8;;\27\\')
      end
    end
  else
    function tty.set_hyperlink() end
  end
end

return tty

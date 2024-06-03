# core.tty.stateful

A mid-level layer that thinks of the terminal as more than just a serial port
but stops short of stateless operations. With that ideal in mind, this module is
responsible for setting up the terminal for a TUI, detecting the terminal's
capabilities, interpreting received terminal events and modifying, querying and
tracking the terminal's state, which encompasses the screen contents, the
cursor, text attributes and screen attributes.

This module sets its __index to `core.tty.system` and extends `getnum` and
`getstr` with the XTGETTCAP feature that some terminals have.

All of the RGB colors below must have their values in the range of 0-255. All
of the "named" colors are the ANSI colors, see `ansi_colors` in the source code
for a list of them. If the color name passed is `nil`, then the terminal default
for that specific context is used. In general, if any other type of argument is
`nil`, then the terminal default is used.

## Initialization

    setup()

*Switch to raw mode, detect terminal capabitilies, load functions, enable some
features and you're good to go!* In other words, this function prepares the
terminal for what's to come - typing tacky text.

    restore()

Restores the terminal to its original state from before `setup()`, so that the
application doesn't brick your terminal.

    detect_caps()

Uses various means (terminfo, XTGETTCAP, other escape sequences, GNOME
Terminal/Konsole/Xfce Terminal/xterm's version environment variable, crystal
ball reading) to automatically detect what the terminal can and cannot do (e.g.
true-color RGB), and populates the `cap` table accordingly. This function
respects the [`NO_COLOR` convention](https://no-color.org/).

    load_functions()

Loads all of the functions whose values depend on the terminal's capabilities,
which includes all of the text and screen attributes functions.

    cap

The table of the current terminal's capabilities, i.e. it contains an entry for
every text and screen attribute. Color caps are `'true_color'`, `'ansi'` or
`false`, everything else is `true` or `false`. You may modify this table and
call `load_functions`, if the automatic capability detection contraption fails
and Skakun, for example, doesn't display colors or undercurls. You may and
*should* also use this table to vary the behaviour of your code to provide the
most suitable visuals, if you are a plugin developer or just a tinkerer.

## Screen contents and cursor movement

    clear()

Clears the screen.

    goto(x, y)

Moves the cursor to the given position on the screen with (1, 1) as the
upper-left corner.

## Text attributes

    reset()

Resets all text attributes to default.

    set_foreground(red, green, blue)
    set_foreground(name)

Sets the text foreground color. The default is usually white.

    set_background(red, green, blue)
    set_background(name)

Sets the text background color. The default is usually black.

    set_bold(is_enabled)

Toggles bold text. The default is usually off.

    set_italic(is_enabled)

Toggles italic text. The default is usually off.

    set_underline(is_enabled)

Toggles underlined text. The default is usually off.

    set_underline_color(red, green, blue)
    set_underline_color(name)

Sets the underline color. The default is usually white.

    set_underline_shape(name)

Sets the underline shape. See `underline_shapes` in the source code for a list.
The default is usually straight underlines.

    set_strikethrough(is_enabled)

Toggles strikethrough text. The default is usually off.

    set_hyperlink(url)

Sets the URL that the text links to. The default is usually the terminal
auto-detecting URLs in text or none at all.

## Screen attributes

    set_cursor(is_visible)

Sets the cursor's visibility. The default is usually visible.

    set_cursor_shape(name)

Sets the cursor shape. See `cursor_shapes` in the source code for a list. The
default is usually a full block.

    set_mouse_shape(name)

Sets the mouse pointer shape shown when hovered over the terminal window. See
`mouse_shapes` in the source code for a list. The default is usually an I-beam.

    set_window_title(text)

Sets the terminal window's title. The default varies from terminal to terminal.

    set_window_background(red, green, blue)
    set_window_background(name)

Sets the terminal window's background color. The default is usually black.

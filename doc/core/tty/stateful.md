# core.tty.stateful

    tty = require('core.tty.stateful')

A mid-level layer that thinks of the terminal as more than just a serial port
but stops short of stateless operations. With that ideal in mind, this module is
responsible for setting up the terminal for a TUI, detecting the terminal's
capabilities, interpreting received terminal events and modifying, querying and
tracking the terminal's state, which encompasses the screen contents, the
cursor, text attributes and screen attributes.

This module sets its __index to `core.tty.system` but overrides `getflag`,
`getnum` and `getstr`.

All of the RGB colors below must have their values in the range of 0-255. All
of the "named" colors are the ANSI colors - see `tty.ansi_colors` for a list of
them. If the color name passed is `nil`, then the terminal's default for that
specific context is used. In general, if any other type of attribute is `nil`,
then the terminal default is used.

## Initialization

    tty.setup()

*Switch to raw mode, detect terminal capabitilies, load functions, enable some
features and you're good to go!* In other words, this function prepares the
terminal for what's to come - typing tacky text. But it does not reset the text
or screen attributes. In addition, if you're in the Linux or FreeBSD console,
then a raw keyboard mode is set and the `Kbd` for the given system becomes the
`tty.input_parser`.

    tty.restore()

Restores the terminal to its original state from before `setup()`, so that the
application doesn't brick your terminal.

    tty.detect_caps()

Uses various means (terminfo, XTGETTCAP, other escape sequences, GNOME
Terminal/Konsole/Xfce Terminal/xterm's version environment variable, crystal
ball reading) to automatically detect what the terminal can and cannot do (e.g.
true-color RGB), and populates the `cap` table accordingly. This function
respects the [`NO_COLOR` convention](https://no-color.org/).

    tty.load_functions()

Loads all of the functions whose values depend on the terminal's capabilities,
which includes all of the text and screen attributes functions.

    value = tty.cap[attr]

The table of the current terminal's capabilities, i.e. it contains an entry for
every text and screen attribute. Color caps are `'true_color'`, `'ansi'` or
`false`; `clipboard` is `'remote'`, `'local'` or `false`; everything else is
`true` or `false`. You may modify this table and call `load_functions`, if the
automatic capability detection contraption fails and Skakun, for example,
doesn't display colors or undercurls. You may and *should* also use this table
to vary the behaviour of your code to provide the most suitable visuals, if you
are a plugin developer or just a tinkerer.

## Events and queries

    events = tty.read_events()
    for _, event in ipairs(events) do
      event.type
      event.button, event.alt, event.ctrl, event.shift
      event.text
      event.x, event.y
    end

Reads in all pending data from the terminal, passes it to `tty.input_parser` and
returns an array of extracted events. `event.type` is one of (button) `'press'`,
`'repeat'`, `'release'`, (text) `'paste'` or (mouse) `'move'`. For button events
`event.button` is the name of the key or mouse button - see `tty.buttons` for a
full list. The `event.alt`, `event.ctrl` and `event.shift` booleans signify
whether the given modifier was pressed during the event and are present in all
types of events for now. `event.x` and `event.y` mark the on-grid
destination/location of the mouse pointer and are present in mouse movement and
mouse button events.

    tty.input_parser

An *input parser* is an object that has a method named `feed`, which consumes
one string of data read from the terminal, and parses and returns as many
events as possible from its internal feed buffer. The default input parser is
`core.tty.input_parser` but switches to `core.tty.linux.kbd` or
`core.tty.freebsd.kbd` at initialization if possible.

    promise = tty.query(question, answer_regex)

Sends off a query (`question` to be exact) and jumps. (This is called
asynchronous I/O.)

    answer = promise()

Forces evaluation of the promise we've been made above by continously reading in
data from the terminal and trying to find a match for the `answer_regex` we gave
it earlier, until `tty.timeout` seconds have passed since the last byte read.
Returns the captures for the match (see `string.match`) or nothing if timed out.
The result is memoized. Note that the terminal's reply will stay in the input
buffer, if you don't evaluate the promise.

    promise1 = tty.getflag(capname, [term])
    promise2 = tty.getnum(capname, [term])
    promise3 = tty.getstr(capname, [term])
    bool, int, string = promise1(), promise2(), promise3()

An asynchronous extension of `core.tty.system`'s terminfo query functions, which
utilizes the XTGETTCAP feature that some terminals provide.

## Screen contents and cursor movement

    tty.sync_begin()

Begins a synchronized update (something like VSync in the terminal world).

    tty.sync_end()

Ends the synchronized update.

    tty.clear()

Clears the screen.

    tty.reset()

Resets all text and screen attributes to default.

    tty.move_to(x, y)

Moves the cursor to the given position on the screen with (1, 1) as the
upper-left corner.

    tty.move_to(x, nil)

Moves the cursor to the given column.

    tty.move_to(nil, y)

Moves the cursor to the given row.

## Text attributes

    tty.set_foreground(red, green, blue)
    tty.set_foreground([name])

Sets the text foreground color. The terminal default is usually white.

    tty.set_background(red, green, blue)
    tty.set_background([name])

Sets the text background color. The terminal default is usually black.

    tty.set_bold([is_enabled])

Toggles bold text. The terminal default is off.

    tty.set_italic([is_enabled])

Toggles italic text. The terminal default is off.

    tty.set_underline([is_enabled])

Toggles underlined text. The terminal default is off.

    tty.set_underline_color(red, green, blue)
    tty.set_underline_color([name])

Sets the underline color. The terminal default is usually white.

    tty.set_underline_shape([name])

Sets the underline shape - see `tty.underline_shapes` for a list. The terminal
default is straight underlines.

    tty.set_strikethrough([is_enabled])

Toggles strikethrough text. The terminal default is off.

    tty.set_hyperlink([url])

Sets the URL that the text links to. The terminal default is usually the
terminal auto-detecting URLs in text or none at all.

## Screen attributes

    tty.set_cursor([is_visible])

Sets the cursor's visibility. The terminal default is visible.

    tty.set_cursor_shape([name])

Sets the cursor shape - see `tty.cursor_shapes` for a list. The terminal default
is usually a full block.

    tty.set_mouse_shape([name])

Sets the mouse pointer shape shown when hovered over the terminal window - see
`tty.mouse_shapes` for a list. The terminal default is usually an I-beam.

    tty.set_window_title([text])

Sets the terminal window's title. The terminal default varies from terminal to
terminal.

    tty.set_window_background(red, green, blue)
    tty.set_window_background([name])

Sets the terminal window's background color. The terminal default is usually
black.

    tty.set_clipboard([text])

Sets the terminal (system) clipboard contents. I don't think the notion of
"terminal default" applies to this one. Nevertheless, passing `nil` will clear
the clipboard.

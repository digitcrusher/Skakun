# core.tty.freebsd.kbd

    Kbd = require('core.tty.freebsd.kbd')

This class exists purely because FreeBSD's keyboard driver can send raw keycodes
or their corresponding Unicode characters but not both at the same time. Thus,
this *input parser* is a full reimplementation of its keycode translation
behaviour with the exception of mouse paste, numeric input of codepoints up to
U+00FF, many "special" key actions, and KDB alternate break sequences.

    kbd = Kbd.new()

Creates a new instance of our input parser. Automatically loads the keymap and
accentmap from the virtual console.

    events = kbd:feed(string)

Feeds the parser a string of encoded keycodes read from the virtual console and
parses as many button events from the parser's input buffer as possible.

    button = Kbd.keycodes[keycode]

A mapping of keycodes to button names. The same object as `keycodes` from
`core.tty.freebsd.system`.

    button = kbd.keycodes[keycode]

Each instance has its own clone of `keycodes`, so you can modify the table per
instance, not globally.

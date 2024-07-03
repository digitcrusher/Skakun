# core.tty.linux.kbd

    Kbd = require('core.tty.linux.kbd')

This class exists purely because Linux's "kbd" input handler can send raw
keycodes or their corresponding Unicode characters but not both at the same
time. Thus, this *input parser* is a full reimplementation of kbd's keycode
translation behaviour with the exception of braille patterns, many key actions
of type `KT_SPEC`, four edge cases involving diacritics, and function key
strings.

    kbd = Kbd.new()

Creates a new instance of our input parser. This will fail if the virtual
console keyboard is in raw mode since it has to load the console's keymap.

    events = kbd:feed(string)

Feeds the parser a string of encoded keycodes read from the virtual console and
parses as many button events from the parser's input buffer as possible.

    button = Kbd.keycodes[keycode]

A mapping of keycodes to button names. The same object as `keycodes` from
`core.tty.linux.system`.

    button = kbd.keycodes[keycode]

Each instance has its own clone of `keycodes`, so you can modify the table per
instance, not globally.

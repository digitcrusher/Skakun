# core.tty.input_parser

    InputParser = require('core.tty.input_parser')
    input_parser = InputParser.new()
    events = input_parser:feed(string)

This is the default terminal input parser. Look in `core.tty.stateful` for the
definition of an input parser.

    InputParser.dispatch_list

The names of the methods that will be tried in sequence when attempting to
parse an event off the input buffer in `feed`. Each method should accept two
arguments - the parser's input buffer and an offset into that buffer - and
should return two values - an array of extracted events or `nil` if matching
failed, and a new offset past the end of the recognized pattern or the old
offset in case of failure. It's allowed to return an empty array, see
`InputParser.drop_kitty_functional_key` for an example.

    key = InputParser.keymap[codepoint]
    key.button, key.ctrl, key.shift, key.text

A reverse keymap that maps codepoints back to keys, used in
`InputParser.take_key`. Modify this, if you have an unusual keyboard layout and
Skakun misidentifies your keys or doesn't report them as buttons at all.

    button = InputParser.kitty_keymap[keycode]

A mapping of Kitty key event keycodes to Skakun button names, used in
`InputParser.take_kitty_key`. You may add additional entries, if you want to use
more of your non-standard (just like your mum) keyboard.

    input_parser.dispatch_list
    input_parser.keymap
    input_parser.kitty_keymap

Each instance has its own clones of these class constants, so you can choose
whether to modify them per class or per instance.

## Pattern matchers

    maybe_events, new_offset = input_parser:take_mouse(buf, offset)

Recognizes a mouse movement or button event.

    maybe_events, new_offset = input_parser:take_kitty_key(buf, offset)

Recognizes a Kitty key press, repeat or release event. Uses
`input_parser.kitty_keymap`.

    maybe_events, new_offset = input_parser:take_functional_key(buf, offset)

Recognizes a functional key press and release.

    maybe_events, new_offset = input_parser:take_functional_key_with_mods(buf, offset)

Recognizes a functional key press and release with modifiers.

    maybe_events, new_offset = input_parser:take_shift_tab(buf, offset)

Recognizes a `Shift+Tab` press and release.

    maybe_events, new_offset = input_parser:take_paste(buf, offset)

Recognizes a bracketed paste event.

    maybe_events, new_offset = input_parser:drop_kitty_functional_key(buf, offset)

Recognizes a Kitty functional key repeat or release event and discards it. This
workaround exists because Kitty sends functional key presses (but not repeats
and releases) using the traditional escape sequences for press-releases and we
have no way of distinguishing them. Giving precedence to Kitty would result in
us failing to detect functional keys releases in other terminals.

    maybe_events, new_offset = input_parser:take_key(buf, offset)

Recognizes a key press and release based on `input_parser.keymap`.

    maybe_events, new_offset = input_parser:take_codepoint(buf, offset)

Recognizes one Unicode codepoint as a paste event.

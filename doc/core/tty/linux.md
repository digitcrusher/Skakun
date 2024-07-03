# core.tty.linux

    linux = require('core.tty.linux')

This module merges `core.tty.linux.system` and `core.tty.linux.kbd` (as `Kbd`),
and should be imported instead of those whenever possible. It exists to allow
complete control over keyboard input in the Linux console.

    linux.enable_raw_kbd()
    linux.disable_raw_kbd()
    input_parser = linux.Kbd.new()

These are the only symbols you'll actually need. Note that you must instantiate
`Kbd` before `enable_raw_kbd()`.

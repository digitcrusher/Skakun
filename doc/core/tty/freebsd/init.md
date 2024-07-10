# core.tty.freebsd

    freebsd = require('core.tty.freebsd')

This module merges `core.tty.freebsd.system` and `core.tty.freebsd.kbd` (as
`Kbd`), and should be imported instead of those whenever possible. It exists to
allow complete control over keyboard input in the FreeBSD console.

    freebsd.enable_raw_kbd()
    freebsd.disable_raw_kbd()
    input_parser = freebsd.Kbd.new()

These are the only symbols you'll actually need.

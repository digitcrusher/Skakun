# core.tty.windows

    windows = require('core.tty.windows')

Just some system-specific functionality for Windows - just like with
`core.tty.linux` and `core.tty.freebsd`.

    windows.set_clipboard([text])

Sets the clipboard to the given UTF-8 string or empties it.

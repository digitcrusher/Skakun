# core.tty.system

    tty = require('core.tty.system')

A low-level layer that contains terminal I/O functions and FFI bindings to
various libraries such as termios and terminfo.

## Initialization

    tty.open()

Opens the terminal pseudofile(s) (`/dev/tty` or `CONIN$`/`CONOUT$`) for reading and writing.

    tty.close()

Closes it/them.

    tty.enable_raw_mode()

Enables raw mode using `cfmakeraw` and makes `read` non-blocking. Explanation of
raw mode: https://en.wikipedia.org/wiki/Terminal_mode

    tty.disable_raw_mode()

Disables raw mode by bringing the terminal back to its original `termios` state.

## Input and output

    tty.write(strings...)

Writes a series of strings to the terminal with full buffering.

    tty.flush()

Flushes the buffered write data and immediately sends it to the terminal.

    string = tty.read()

Reads all pending bytes from the terminal.

## Terminfo

Functions to query the system-wide terminfo database, which contains
a description of terminals' capabilities. All functions take an optional `term`
argument, which is the terminal name to be looked up in the database. If absent,
it takes on the name of the terminal the application is being run in. That is
usually `os.getenv('TERM')` but the exact behaviour is specified in ncurses'
source code since that's the blackbox doing the hard work for us.

See `man 5 terminfo` for more information on terminfo. Note that the list of
capabilities in that man page does not contain any of the commonly-used
extensions, such as `Ss`.

    bool = tty.getflag(capname, [term])

Returns a boolean signalling the presence of a terminal flag capability in its
terminfo entry, or `nil` if the capname is unrecognized.

    int = tty.getnum(capname, [term])

Gets the numeric capability, or `false` if it's absent from the terminal's
terminfo entry, or `nil` if the capname is unrecognized.

    string = tty.getstr(capname, [term])

Gets the string capability, or `false` if it's absent from the terminal's
terminfo entry, or `nil` if the capname is unrecognized.

Alas, the terminfo database has a reputation of not being the most reliable nor
up-to-date and sadly there's no better widespread way to query the terminal's
capabilities. To give you a sense of the common problems around terminfo, on my
Debian machine xterm sets `$TERM` to `xterm` instead of `xterm-256color` and
that stops terminfo from knowing that my terminal has the `initc` capability,
i.e. it has a configurable palette of 256 24-bit RGB colors.

However, there is a light of hope called "XTGETTCAP", which is a terminfo query
as an escape sequence sent directly to the terminal, and not to some outdated
file that may not even be on the same computer as the running terminal, and
therefore should be preferred when available, which is exactly what
`core.tty.stateful` does. Now we just have to wait for the developers of
terminal emulators to actually start implementing it.

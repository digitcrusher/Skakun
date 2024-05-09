# core.tty

Everything needed to read input from the user and get stuff on the screen,
*in the terminal 😎*. This gigantic code ~~mess~~ is split up into two layers,
each successively building upon the former:

- `core.tty.system` - containing basic I/O functions treating the terminal as
  a dumb serial port and high-level FFI bindings to termios and terminfo, and
- `core.tty.stateful` - having knowledge of the terminal's wonderful capabilities
  and using that to modify, query and keep track of its global state.

Importing `core.tty` returns a unified table containing symbols from both of
them, so please see the documentation pages for the respective submodules.

We chose not to use any existing library, such as ncurses, for Skakun's terminal
interface because none of them supports all the features of every terminal in
existence and, furthermore, implementing a custom, open solution in Lua gives
the end user more freedom of extensibility in that regard.

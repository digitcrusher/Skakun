# core.tty.unix

This module merges `core.tty.unix.kbd` (as `Kbd`) and `core.tty.unix.vt` and
should be imported instead of those whenever possible. It exists to allow
complete control over keyboard input in the Linux console.

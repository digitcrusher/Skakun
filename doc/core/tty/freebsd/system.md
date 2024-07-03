# core.tty.freebsd.system

    system = require('core.tty.freebsd.system')

Bindings to the ioctls of the FreeBSD "newcons" driver. This namespace contains
various constants from `<sys/kbio.h>` and `<dev/kbd/kbdreg.h>` that are used by
`core.tty.freebsd.kbd`. Beware that the constants for "special" key actions have
been bitwise OR'ed with `SPCLKEY` to simplify `core.tty.freebsd.kbd`'s
implementation. All of the functions below act upon the current virtual console.

    system.enable_raw_kbd()

Sets the keyboard mode to `K_CODE` (`KDGKBMODE` and `KDSKBMODE`).

    system.disable_raw_kbd()

Restores the original keyboard mode (`KDSKBMODE`).

    keymap = system.get_keymap()
    action = keymap[keycode][modifiers]
    keymap[keycode].flags

Gets the key translation table (`GIO_KEYMAP`). The table is `nil` in places
where it would normally be `NOP` in C code. As with the key action constants,
entries marked as special by the `spcl` C field are bitwise OR'ed with
`SPCLKEY` to simplify things. `flags` corresponds to C `flgs`.

    accentmap = system.get_accentmap()
    codepoint_or_accent = accentmap[accent][codepoint_or_accent]

Gets the accent table (`GIO_DEADKEYMAP`). `accchar` is mapped as U+0020 SPACE.

    system.set_kbd_locks(flags)

Sets the state of the keyboard driver's flags for the "Lock" keys (`KDSKBSTATE`).

    flags = system.get_kbd_locks()

Gets the state of the keyboard driver's flags (`KDGKBSTATE`).

    system.set_active_vc(num)

Switches the currently visible virtual console (`VT_ACTIVATE`). The number of
the first console is of course at the whim of FreeBSD, but it just so happens
that it's always been `1`.

    num = system.get_active_vc()

Gets the number of the currently visible virtual console (`VT_GETACTIVE`).

    button = system.keycodes[keycode]

A mapping of the most common keycodes to Skakun's button names.

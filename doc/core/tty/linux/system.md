# core.tty.linux.system

    system = require('core.tty.linux.system')

Bindings to the ioctls of the Linux "vt" driver. All of the functions below act
upon the current virtual console.

    system.enable_raw_kbd()

Sets the keyboard mode to `K_MEDIUMRAW` (`KDGKBMODE` and `KDSKBMODE`).

    system.disable_raw_kbd()

Restores the original keyboard mode (`KDSKBMODE`).

    keymap = system.get_keymap()
    action = keymap[modifiers][keycode]

Gets the key translation table (`KDGKBENT`). Doesn't work in raw keyboard mode.
The table is `nil` in places where it would normally be `K_HOLE` or
`K_NOSUCHMAP` in C code.

    accentmap = system.get_accentmap()
    codepoint_or_accent = accentmap[accent][codepoint_or_accent]

Gets the accent table (`KDGKBDIACRUC`).

    system.set_kbd_locks(caps_lock, num_lock, scroll_lock)

Sets the state of the keyboard handler's flags for the "Lock" keys (`KDSKBLED`).

    caps_lock, num_lock, scroll_lock = system.get_kbd_locks()

Gets the state of the keyboard handler's flags (`KDGKBLED`).

    system.set_active_vc(num)

Switches the currently visible virtual console (`VT_ACTIVATE`). The number of
the first console is of course at the whim of Linux, but it just so happens that
it's always been `1`.

    num = system.get_active_vc()

Gets the number of the currently visible virtual console (`TIOCL_GETFGCONSOLE`).

    button = system.keycodes[keycode]

A mapping of the most common keycodes from `<linux/input-event-codes.h>` to
Skakun's button names.

    value = system.K[name]
    value = system.KG[name]
    value = system.KT[name]

The constants from `<linux/keyboard.h>` that are used in `core.tty.linux.kbd`
and whose names start with `K_`, `KG_` and `KT_` respectively.

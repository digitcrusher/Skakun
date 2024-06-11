# core.tty.unix.vt

A module for communicating with Linux's `vt` driver (and FreeBSD's too)

    enable_raw_kbd()

    disable_raw_kbd()

    get_keymap()[shift_final][keycode]

    get_accentmap()[accent][codepoint]

    set_kbd_leds(caps_lock, num_lock, scroll_lock)

    caps_lock, num_lock, scroll_lock = get_kbd_leds()

    set_active_vc(num)

    get_active_vc()

# core.tty.unix.kbd

This module exists purely because Linux's `kbd` input handler can send raw keycodes or their corresponding unicode characters but not both at the same time.

    Kbd.new()

    Kbd:feed(string)

# core.utils

*And now, ladies and gentlemen. Please welcome, your favourite side-character
starring in every blockbuster codebase in existence, Utils!*

    lock_globals()

Sets a metatable for the global variables table `_G` that prevents users from
accidentally defining global variables and accessing nonexistent local or global
variables. You can still create new globals using `rawset`.

    unlock_globals()

Resets `_G`'s metatable, thereby undoing `lock_globals`.

    hex_encode(string)

Converts a string into hexadecimal bytes and concatenates them.

    hex_decode(hex)

Decodes a series of hexadecimal pairs corresponding to the bytes of a string.

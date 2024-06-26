# Goals
- Modal editing with multiple selections and emphasis on visual feedback and discoverability (Kakoune-style)
- Optimized for editing huge files
- Not just a code editor - support for binary files
- Let the user modify every behavior with Lua (Lite-or-Emacs-style)
- Make the most out of the terminal
- More forward-looking than backwards-compatible


We need:
- mouse clicks, drags, scrolls
- ctrl, alt, shift modifiers
- wide character support
- non-blocking character input
- multi-codepoint emojis


The following terminals have first-class support:
- GNOME Terminal
- kitty
- Konsole
- Linux console
- st
- Windows Terminal
- Xfce Terminal
- xterm

2. Install GIO and ncurses (`apt install libglib2.0-dev libncurses-dev` on Debian)

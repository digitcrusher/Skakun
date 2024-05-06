# Goals
- Modal editing with multiple selections and emphasis on visual feedback and discoverability (Kakoune-style)
- Optimized for editing huge files
- Not just a code editor - support for binary files
- Let the user modify every behavior with Lua (Lite-or-Emacs-style)
- Make the most out of the terminal


We need:
- 24-bit colors
- fancy fonts effects (underlines etc.)
- mouse clicks, drags, scrolls
- mouse pointer sprite change
- whole screen buffering for flashes
- restore terminal view from before
- ctrl, alt, shift modifiers
- wide character support
- support for old terminals and windows
- non-blocking character input
- multi-codepoint emojis


we don't want to do termios, escape sequences, terminfo

CIEDE2000 for color approximation

- Alacritty
- GNOME Terminal
- Kitty
- Konsole
- ssh
- st
- tmux
- urxvt
- Windows Terminal
- Xfce Terminal
- xterm

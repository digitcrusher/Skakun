# Troubleshooting Skakun

## Copying to system clipboard doesn't work.

### If `tty.cap.clipboard` is `'remote'`…

Then it means that your terminal formally supports the OSC 52 escape sequence, but that they have been disabled in your terminal's settings, usually for security reasons. You can either [enable them back on](https://github.com/tmux/tmux/wiki/Clipboard) or make Skakun use the local system clipboard tools by setting `tty.cap.clipboard` to `'local'`. Don't forget to `tty.load_functions()` afterwards.

### Otherwise…

It means you probably don't have any of `xclip`, `xsel` or `wl-copy` installed. Install one of your choice.

## Skakun crashed and now my terminal is unusable.

If you're in the Linux console, press `Ctrl+PrtScr+R` to reset the keyboard mode, as per [Linux's documentation](https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html). Run the command `reset` in the shell to restore everything else.

## Skakun froze in the Linux console and now my keyboard is unresponsive.

Press `Ctrl+PrtScr+K` to kill all processes in the current console, as per [Linux's documentation](https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html). This key combination unfortunately does not have a counterpart on FreeBSD.

# Troubleshooting Skakun

## Skakun froze in the Linux console and now my keyboard is unresponsive.

Press `Ctrl+PrtScr+K` to kill all processes in the current console, as per [Linux's documentation](https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html). This key combination unfortunately does not have a counterpart on FreeBSD.

## Skakun crashed and now my terminal is unusable.

If you're in the Linux console, press `Ctrl+PrtScr+R` to reset the keyboard mode, as per [Linux's documentation](https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html). Run the command `reset` in the shell to restore everything else.

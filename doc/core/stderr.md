# core.stderr

    stderr = require('core.stderr')

Stderr redirected to a file is the standard way of logging in Skakun. Storing
the logs in a file allows us to display them to the user during runtime and
access them after exit. Moreover, we reuse stderr to prevent child processes
from writing their error messages to the terminal screen (the usual initial
target of stderr).

    -- At the top of the source file:
    local here = ...

    stderr.error(here, ...)
    stderr.warn(here, ...)
    stderr.info(here, ...)
    stderr.log(level, here, ...)

Sends a log message of the given severity to stderr in a standard format. The
trailing arguments are automatically converted to string and concatenated.
`stderr.log` should be used only to set a custom message format.

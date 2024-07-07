# core

    core = require('core')

This namespace is wholly populated by the bootstrap program.

    core.add_cleanup(func)

Registers a function to be called at program failure or normal exit. The call
order is opposite to the order of registration. The function may be called more
than once, so subsequent calls should probably be no-ops.

    core.platform

The operating system we're on - `'linux'`, `'windows'`, `'macos'` or
`'freebsd'`.

    core.config_dir

The absolute path to Skakun's config directory.

    core.args

Command-line arguments, including the executable's name.

    core.version

Skakun's version string, e.g. `'1.2.3-dirty+22552eb'`.

    core.exe_dir

The absolute path to the directory containing the Skakun executable.

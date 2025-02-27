# core

    core = require('core')

This namespace is wholly populated by the bootstrap program and is available to
C modules.

    core.add_cleanup(func)

Registers a function to be called at program failure or normal exit. The call
order is opposite to the order of registration.

    core.platform

The operating system we're on - `'linux'`, `'windows'`, `'macos'` or
`'freebsd'`.

    core.config_dir

The absolute path to Skakun's config directory.

    core.args

Command-line arguments, including the executable's name.

    core.should_forward_stderr_on_exit

Indicates whether our file-backed stderr will be copied back to the original
stderr on program exit or failure. You will most likely want to change this to
`false` on startup. Automatically resets to `true` whenever a cleanup function
or the `user` module errors.

    core.stderr_path

The path to the file which stderr writes to.

    core.version

Skakun's version string, e.g. `'1.2.3-dirty+22552eb'`.

    core.exe_dir

The absolute path to the directory containing the Skakun executable.

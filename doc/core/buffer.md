# core.buffer

    Buffer = require('core.buffer')

An efficient string buffer designed with huge files in mind and implemented
using an implicit treap (similar to a rope), which enables editing operations
in logarithmic time.

Please note that the `#buffer` factor in some of the time complexities below is
a great overstatement, unless the buffer's internal node structure is very
fractured, e.g. when inserting one character at a time in random places.

    buffer = Buffer.new()

Creates a new empty buffer. (duh!)

    buffer = Buffer.open(path_or_uri)

Creates a new buffer from a local file or
a [GIO](https://en.wikipedia.org/wiki/GIO_(software)) URI. The configuration
variable `Buffer.max_open_size` controls the size threshold at which file
contents will be memory-mapped (mmap) instead of being read from disk all at
once. The time complexity is `O(min(#buffer, Buffer.max_open_size))` for native
files and `O(#buffer)` for GIO files.

    buffer:save(path_or_uri)

Saves the buffer in `O(#buffer)`. If the destination is one of our memory-mapped
file, then that file will be renamed to a unique random name (such as
`.buffer.md.skak-22552ebf`) to prevent corrupting existing buffers. Skakun
deletes all such backups on exit. Beware that, even if the backup file has been
externally renamed, moved, modified or deleted, the editor will still try to
delete a file under the same name in the original directory.

## Editing

An **important** notice: The following functions operate on zero-based indices
and the intervals are open (last element excluded). It's best to think that the
offsets don't point at elements but rather at the spaces between them.

    len = #buffer

The number of bytes in the buffer.

    string = buffer:read(start, end)

Returns a portion of the buffer as a string in `O(log #buffer + end - start)`.

    buffer:insert(offset, string)

Inserts a string into the buffer in `O(log #buffer + #string)`.

    buffer:delete(start, end)

Deletes a range from the buffer in `O(log #buffer)`.

    buffer:copy(offset, src, start, end)

Copies and inserts a slice from another buffer in `O(log #buffer + log #src)`.
A `O(log #src)` cost applies to memory but that is cached whenever the state of
the source buffer and the slice stay the same.

    Buffer.clear_copy_cache()

Clears the aforementioned cache.

## Freezing

    buffer:freeze()

Marks a buffer and its contents as read-only causing any future edit operations
to fail.

    bool = buffer:is_frozen()

Checks whether a buffer is frozen.

    self_or_copy = buffer:thaw()

Returns self or, if the buffer is frozen, an unfrozen writable copy of it.

## Mmaps

Mmaps, in all their glory, are not without their downsides. The fact that we
don't waste time on loading files allows us to save precious time, but on the
other hand makes the internal representation of our buffers vulnerable to
external actors who may try to modify the contents of our memory-mapped files.
Whenever such an event occurs, the memory-mapped parts of the buffer become
completely unusuable and are zeroed out - in other words: corrupt. Thus, it's
a good idea to allow the user to request the complete loading of an opened
buffer at will.

    buffer:load()

Loads all healthy (non-corrupt) mmaps in a buffer immediately from disk in
`O(#buffer)`.

    bool = buffer:has_healthy_mmap()
    bool = buffer:has_corrupt_mmap()

Checks whether a buffer contains any healthy/corrupt mmaps.

    were_mmaps_corrupted = Buffer.validate_mmaps()

Checks the filesystem for any changes made to memory-mapped files and updates
all buffers accordingly in `O(#buffer)`.

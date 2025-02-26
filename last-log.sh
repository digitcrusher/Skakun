#!/bin/sh

tail -n +1 "$@" "$XDG_RUNTIME_DIR/skakun/$(ls "$XDG_RUNTIME_DIR/skakun" | sort -n | tail -n 1)"

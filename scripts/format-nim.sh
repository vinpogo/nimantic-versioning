#!/usr/bin/env bash
# Wrapper for editor format-on-save. Exists because Zed's external
# formatter does not expand `~` or `$HOME` in `command`, so we can't
# point it directly at the mise shim. Shell handles the expansion here
# and exec's into the actual formatter.
#
# Used by `.zed/settings.json`. Forwarded args (typically `-`) are
# passed through to nph unchanged.

exec "$HOME/.local/share/mise/shims/nph" "$@"

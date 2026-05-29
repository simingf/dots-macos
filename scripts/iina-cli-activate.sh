#!/bin/sh
# iina-cli always exec's IINA as a subprocess that inherits the shell's controlling
# tty — macOS then refuses to grant menu-bar focus. Launch via `open` instead so IINA
# goes through launchd; IINA parses the same --mpv-* / --no-stdin flags directly.
exec /usr/bin/open -na IINA --args "$@"

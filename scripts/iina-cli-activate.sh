#!/bin/sh
# iina-cli exec's IINA from the shell's (non-GUI) session → no menu bar / focus.
# `open` launches it via launchd; IINA takes the same --mpv-* / --no-stdin flags.
exec /usr/bin/open -na IINA --args "$@"

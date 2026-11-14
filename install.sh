#!/bin/sh
# Legacy entry point; the main installer is lwinstall.sh.
# Compatibility entry point for existing installation instructions.
cd "$(dirname "$0")" || exit 1
exec sh ./lwinstall.sh "$@"

#!/bin/sh
# Select a language for installation or update an existing deployment.
# PolyForm Noncommercial License 1.0.0: https://polyformproject.org/licenses/noncommercial/1.0.0
: <<'LAN_WATCH_NOTICE'
Required Notice: Copyright 2026 fmase (@mcmas)
LAN_WATCH_NOTICE
set -eu
cd "$(dirname "$0")"
case "${1:-}" in --preview) export LAN_WATCH_PREVIEW=1;; '') ;; *) echo 'Usage: sh lwinstall.sh [--preview]' >&2; exit 1;; esac
# License and required notice accompany the installer, including upgrades.
printf '\n  LAN WATCH - PolyForm Noncommercial License 1.0.0\n  Only noncommercial use as permitted by the license.\n  https://polyformproject.org/licenses/noncommercial/1.0.0\n  Required Notice: Copyright 2026 fmase (@mcmas)\n\n'
# An existing installation keeps its language and configuration during upgrade.
if [ -e /usr/lib/aaaia-lan-monitor ] || [ -e /etc/init.d/aaaia-lan-monitor ] || [ -e /etc/aaaia-lan-monitor.conf ]; then
  exec sh ./upgrade.sh
fi
version=$(cat VERSION)
green=; dim=; reset=;
printf '\n  %sL A N   W A T C H%s\n  %sv%s    made by github.com/fmase%s\n\n  %s[1]%s  Italiano\n  %s[2]%s  English\n\n  %s>%s Lingua / Language: ' "$green" "$reset" "$dim" "$version" "$reset" "$green" "$reset" "$green" "$reset" "$green" "$reset"
read -r language
case "$language" in 1) exec sh ./install-it.sh;; 2) exec sh ./install-en.sh;; *) echo 'Scelta non valida / Invalid choice' >&2; exit 1;; esac

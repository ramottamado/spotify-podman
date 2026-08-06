#!/bin/env bash

# Use system xdg utilities. But first create mimeapps.list if it doesn't
# exist; some systems have bugs in xdg-mime that make it fail without it.
xdg_app_dir="${XDG_DATA_HOME:-$HOME/.local/share/applications}"
mkdir -p "$xdg_app_dir"
[ -f "$xdg_app_dir/mimeapps.list" ] || touch "$xdg_app_dir/mimeapps.list"

xdg-settings set default-web-browser org.gnome.Epiphany.desktop

(python3 "/usr/local/bin/spotify-inhibitor.py") &

(/usr/share/spotify/spotify "$@") &

wait -n

kill 0

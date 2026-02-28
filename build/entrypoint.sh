#!/bin/env bash

if [ "$EUID" -ne 0 ]; then
	mkdir -p "$HOME/.local/share" "$HOME/.config" && chown -R 1000:1000 "$HOME"
fi

xdg-settings set default-web-browser org.gnome.Epiphany.desktop

exec -a "$0" "/usr/share/spotify/spotify" "$@"

#!/bin/env bash

xdg-settings set default-web-browser org.gnome.Epiphany.desktop

exec -a "$0" "/usr/share/spotify/spotify" "$@"

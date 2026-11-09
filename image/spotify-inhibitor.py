#!/usr/bin/env python3
import signal

import gi

gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix

INHIBIT_SUSPEND = 4

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
players = {}  # sender -> PlaybackStatus
cookie = None


def session_manager(method, args):
    return bus.call_sync(
        "org.gnome.SessionManager",
        "/org/gnome/SessionManager",
        "org.gnome.SessionManager",
        method,
        args,
        None,
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )


def update():
    global cookie
    playing = "Playing" in players.values()
    try:
        if playing and cookie is None:
            reply = session_manager(
                "Inhibit",
                GLib.Variant(
                    "(susu)", ("Spotify", 0, "Spotify is playing", INHIBIT_SUSPEND)
                ),
            )
            cookie = reply.unpack()[0]
            print("▶ Spotify playing. Inhibiting suspend...")
        elif not playing and cookie is not None:
            session_manager("Uninhibit", GLib.Variant("(u)", (cookie,)))
            cookie = None
            print("⏸ Spotify paused or stopped. Removing inhibition...")
    except GLib.Error as e:
        print(f"Inhibit call failed: {e.message}")


def on_properties_changed(conn, sender, path, iface, sig, params, data):
    _, changed, _ = params.unpack()
    if "PlaybackStatus" in changed:
        players[sender] = changed["PlaybackStatus"]
        update()


bus.signal_subscribe(
    None,
    "org.freedesktop.DBus.Properties",
    "PropertiesChanged",
    "/org/mpris/MediaPlayer2",
    "org.mpris.MediaPlayer2.Player",
    Gio.DBusSignalFlags.NONE,
    on_properties_changed,
    None,
)

loop = GLib.MainLoop()


def stop(*_):
    loop.quit()
    return GLib.SOURCE_REMOVE


GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)
GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)

loop.run()

players.clear()
update()

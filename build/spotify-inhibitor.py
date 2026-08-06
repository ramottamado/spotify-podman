#!/usr/bin/env python3

import sys
import signal
from pydbus import SessionBus
from gi.repository import GLib

# GNOME SessionManager.Inhibit flags
INHIBIT_SUSPEND = 4
INHIBIT_IDLE = 8


class SpotifyInhibitorDaemon:
    def __init__(self):
        self.bus = SessionBus()
        try:
            self.sm = self.bus.get(
                "org.gnome.SessionManager", "/org/gnome/SessionManager"
            )
        except Exception as e:
            print(f"Error: GNOME SessionManager not found. ({e})", file=sys.stderr)
            sys.exit(1)

        self.cookie = None
        self.players = {}  # Map[unique_name (str) -> PlaybackStatus (str)]

        # 1. Fetch current status of any already-open Spotify instances
        dbus_proxy = self.bus.get(".DBus")
        for name in dbus_proxy.ListNames():
            if name.startswith("org.mpris.MediaPlayer2.spotify"):
                try:
                    unique_name = dbus_proxy.GetNameOwner(name)
                    self._update_player_status(unique_name)
                except Exception:
                    continue

        # 2. Monitor for Play/Pause/Stop actions
        self.bus.subscribe(
            iface="org.freedesktop.DBus.Properties",
            signal="PropertiesChanged",
            arg0="org.mpris.MediaPlayer2.Player",
            signal_fired=self._on_properties_changed,
        )

        # 3. Monitor for Spotify opening, closing, or crashing
        self.bus.subscribe(
            sender="org.freedesktop.DBus",
            iface="org.freedesktop.DBus",
            signal="NameOwnerChanged",
            signal_fired=self._on_name_owner_changed,
        )

    def _update_player_status(self, unique_name):
        try:
            # This is a blocking call in pydbus, so we don't have to worry about
            # overlapping signals modifying the state while we wait.
            player = self.bus.get(unique_name, "/org/mpris/MediaPlayer2")
            status = player.PlaybackStatus
            self.players[unique_name] = status
        except Exception:
            # Ignore if Spotify crashes mid-request
            pass
        finally:
            self._evaluate_inhibit()

    def _on_properties_changed(self, sender, object_path, iface, signal, params):
        interface_name, changed_properties, invalidated_properties = params

        # STRICT GATEKEEPER: Only care if the sender is a known Spotify instance
        if sender in self.players and "PlaybackStatus" in changed_properties:
            self.players[sender] = changed_properties["PlaybackStatus"]
            self._evaluate_inhibit()

    def _on_name_owner_changed(self, sender, object_path, iface, signal, params):
        name, old_owner, new_owner = params

        # Case A: A Spotify instance appeared or closed gracefully
        if name.startswith("org.mpris.MediaPlayer2.spotify"):
            if old_owner and old_owner in self.players:
                del self.players[old_owner]
                self._evaluate_inhibit()

            if new_owner:
                self._update_player_status(new_owner)

        # Case B: Ghost Crash - A Spotify process was forcefully killed (e.g. SIGKILL).
        # It drops its raw connection ID (which starts with ':') without cleaning up.
        elif name.startswith(":") and not new_owner:
            if name in self.players:
                del self.players[name]
                self._evaluate_inhibit()

    def _evaluate_inhibit(self):
        is_playing = any(status == "Playing" for status in self.players.values())

        if is_playing and self.cookie is None:
            print("▶ Spotify started. Inhibiting GNOME session idle/suspend...")
            try:
                self.cookie = self.sm.Inhibit(
                    "Spotify Inhibitor",
                    0,
                    "Spotify is currently playing",
                    INHIBIT_SUSPEND,
                )
            except Exception as e:
                print(f"Failed to inhibit GNOME: {e}")

        elif not is_playing and self.cookie is not None:
            print("⏸ Spotify paused or stopped. Removing inhibition...")
            try:
                self.sm.Uninhibit(self.cookie)
            except Exception as e:
                print(f"Failed to uninhibit GNOME: {e}")
            self.cookie = None

    def run(self):
        loop = GLib.MainLoop()

        # Natively bind POSIX interrupt signals to cleanly stop the GLib loop
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, loop.quit)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, loop.quit)

        print("Daemon started. Monitoring ONLY Spotify D-Bus signals...")
        self._evaluate_inhibit()

        loop.run()

        print("\nExiting daemon...")
        if self.cookie is not None:
            try:
                self.sm.Uninhibit(self.cookie)
            except Exception as e:
                print(f"Failed to uninhibit during exit: {e}")


if __name__ == "__main__":
    daemon = SpotifyInhibitorDaemon()
    daemon.run()

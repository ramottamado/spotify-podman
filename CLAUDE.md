# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Runs the Spotify desktop client in a rootless Podman container on a Wayland (GNOME) host. Images are built by Podman Quadlet `.build` units under systemd `--user`. A host-side launcher script starts the container with a filtered D-Bus session bus. There is no test suite or linter config. Everything is shell, Python (PyGObject), Containerfiles and systemd/Quadlet unit files.

## Commands

Run these on the host. Use `make -n <target>` to preview a target anywhere.
```sh
make install            # quadlet + build + launcher + desktop + icons
make install BUILD=no   # same, but skip rebuilding the images
make quadlet            # render *.build.in into build/ and install units + build context
make build              # quadlet, then start spotify-base-build and spotify-build (blocking oneshots)
make launcher           # install bin/spotify -> ~/.local/bin/spotify
make desktop icons      # extract the .desktop file and hicolor icons from the built image
make uninstall          # remove container, images, quadlet units + context, launcher, .desktop, icons
make clean              # remove the build/ scratch dir
IN_TOOLBOX=yes|no      # auto-detected via /run/.toolboxenv; in toolbox, podman/systemctl run on the host via flatpak-spawn
journalctl --user -u spotify-build -f
```
After editing anything under `quadlet/spotify/`, run `make build`. It copies the build context into `~/.config/containers/systemd/spotify` before it rebuilds.

Run: `~/.local/bin/spotify [args]` (a copy of `bin/spotify`).

The devcontainer (`.devcontainer/`) is only for editing. It has no Podman, systemd user session, Wayland or D-Bus, so the build and run steps above can't be checked from inside it.

## Architecture

**Two-stage image build via Quadlet.** `quadlet/*.build.in` are templates. `make quadlet` replaces `%HOMEDIR%` with `$HOME` and installs them, using `podman quadlet install` when it's available and otherwise copying them into `~/.config/containers/systemd/`. It also copies the whole `quadlet/spotify/` directory there, because both builds use it as their working directory and build context.
- `Containerfile.base` (`Pull=newer`) is Ubuntu 26.04 plus the Spotify apt repo and runtime deps (`spotify-client`, fonts, GL, `python3-gi`, `rsync`). It also installs the helper scripts into `/usr/local/bin`.
- `Containerfile` (`Pull=never`, `--no-cache`) builds on the local base image. It runs `dist-upgrade` and creates the UID/GID 1000 `spotify` user (replacing the stock `ubuntu` user). Because of `--no-cache`, every rebuild picks up Spotify updates.
- `systemd/spotify-build.timer` is meant to trigger a weekly rebuild. Nothing installs it.
- `quadlet/spotify/ubuntu.sources` (a noble mirror) is not referenced by either Containerfile.

**Host launcher (`bin/spotify`).** It needs `WAYLAND_DISPLAY` and `XAUTHORITY`. If a `spotify` container is already running, it forwards the args with `podman exec`, so the client stays single-instance. Otherwise it starts `xdg-dbus-proxy` on `$XDG_RUNTIME_DIR/spotify-bus` and mounts that socket as the container's session bus. The container runs with `--userns=keep-id`, `--cap-drop=all` and host network/IPC. It also gets PipeWire/Pulse sockets, `/dev/dri`, and the XDG user dirs read-only. `~/.local/share/spotify` is persisted as the container's `/home/spotify`.

**D-Bus allowlist ties the pieces together.** Every D-Bus interaction a container-side script makes must be allowed by a matching `--talk`/`--call`/`--own`/`--broadcast` rule in `bin/spotify`, or it fails silently inside the container:
- `entrypoint.sh` registers `org.gnome.Epiphany.desktop` as the default web browser. That desktop file runs `default-browser`, which opens links on the host through `org.freedesktop.portal.OpenURI`.
- `spotify-inhibitor.py` listens for MPRIS `PropertiesChanged` broadcasts. While anything is `Playing`, it calls `org.gnome.SessionManager.Inhibit`/`Uninhibit` (suspend flag 4).
- Spotify itself owns `org.mpris.MediaPlayer2.spotify*` and uses Notifications and portal Settings.

`entrypoint.sh` runs the inhibitor and Spotify side by side, uses `wait -n`, then `kill 0`. If either process exits, the container stops.

**Host integration.** `make desktop`/`make icons` read the `.desktop` file and hicolor icons out of the built image with throwaway `podman run` calls. `make desktop` rewrites `Exec=` to point at `~/.local/bin/spotify`.

## Conventions

- Image names (`tamado.codes/library/...`) and the base tag `26.04` are hard-coded in the `.build.in` files, `Containerfile`, `Makefile` and `bin/spotify`. Change them in all of these places together.
- Container-side Python uses only the PyGObject (`gi`) from the image's `python3-gi`, with no pip dependencies.

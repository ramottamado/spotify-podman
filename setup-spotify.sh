#!/bin/bash

set -ex

QUADLET_DIR="$HOME/.config/containers/systemd"

# Reference: http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SOURCE="${BASH_SOURCE[0]}"
BIN_DIR="$(dirname "$SOURCE")"
while [ -h "$SOURCE" ]; do
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$BIN_DIR/$SOURCE"
	BIN_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
done
BIN_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

main() {
	echo "Starting Spotify setup script..."

	copy_quadlet_files
	build_images

	install_spotify
	create_wrapper
	create_desktop_file
	sync_icons

	echo "Spotify setup script completed successfully."
}

copy_quadlet_files() {
	echo "Installing quadlet files..."

	sed -E "s|%HOMEDIR%|${HOME}|g" "${BIN_DIR}/quadlet/spotify-base.build.in" >"/tmp/spotify-base.build"
	sed -E "s|%HOMEDIR%|${HOME}|g" "${BIN_DIR}/quadlet/spotify.build.in" >"/tmp/spotify.build"

	if podman quadlet list; then
		podman quadlet install --replace --reload-systemd /tmp/spotify-base.build
		podman quadlet install --replace --reload-systemd /tmp/spotify.build
	else
		mkdir -p "$QUADLET_DIR"
		cp -p /tmp/spotify-base.build "$QUADLET_DIR"
		cp -p /tmp/spotify.build "$QUADLET_DIR"
	fi

	cp -r "${BIN_DIR}/quadlet/spotify" "$QUADLET_DIR"
}

build_images() {
	read -rp "Please select whether you want to build the images now [Y/n]: " -n 1
	echo ""
	if [[ -z $REPLY || $REPLY =~ ^[Yy]$ ]]; then
		systemctl --user daemon-reload
		systemctl --user start spotify-base-build
		systemctl --user start spotify-build
	else
		echo "Skipping build images."
	fi
}

install_spotify() {
	if ! podman image exists tamado.codes/library/spotify:latest; then
		echo "Please build Spotify image first."
		exit 1
	fi
}

create_wrapper() {
	cp -f "${BIN_DIR}/bin/spotify" "$HOME"/.local/bin/spotify

	chmod +x "$HOME"/.local/bin/spotify
	echo "Created Spotify launcher script at $HOME/.local/bin/spotify"
}

create_desktop_file() {
	podman run --rm \
		--user 0 \
		--entrypoint '["/bin/bash", "-c"]' \
		--security-opt label=disable \
		tamado.codes/library/spotify:latest \
		'sed -e "/^TryExec.*/d" -e "/^Exec.*/d" /usr/share/spotify/spotify.desktop' >/tmp/spotify.desktop

	if [ -f /tmp/spotify.desktop ]; then
		echo "Temporary Spotify desktop file created."
	else
		echo "Failed to create temporary Spotify desktop file. Exiting."
		exit 1
	fi

	echo "Exec=${HOME}/.local/bin/spotify %U" >>/tmp/spotify.desktop
	cp -f /tmp/spotify.desktop "$HOME/.local/share/applications/spotify.desktop"
}

sync_icons() {
	echo "Syncing application icons..."

	mkdir --parent "$HOME/.local/share/icons/hicolor"

	podman run --rm \
		--user 0 \
		--entrypoint '["/bin/bash", "-c"]' \
		--security-opt label=disable \
		--volume "$HOME/.local/share/icons/hicolor:/hicolor" \
		tamado.codes/library/spotify:latest \
		'rsync -rav --prune-empty-dirs --include="*/" --include="spotify-client.png" --exclude="*" /usr/share/icons/hicolor/* /hicolor'
}

main

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

	mkdir -p "$QUADLET_DIR"
	cp -r "${BIN_DIR}/quadlet/spotify" "$QUADLET_DIR"
	sed -E "s|%HOMEDIR%|${HOME}|g" "${BIN_DIR}/quadlet/spotify-base.build.in" >"${QUADLET_DIR}/spotify-base.build"
	sed -E "s|%HOMEDIR%|${HOME}|g" "${BIN_DIR}/quadlet/spotify.build.in" >"${QUADLET_DIR}/spotify.build"
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
	cat <<'EOF' >"$HOME"/.local/bin/spotify
#!/bin/bash

. "${HOME}/.config/user-dirs.dirs"

mkdir --parent "$HOME/.local/share/spotify"

if podman container exists spotify; then
	podman container rm spotify

	if [[ $?!=0 ]]; then
		podman container exec spotify spotify "$@"
		exit 0
	fi
fi

podman container run --rm --name spotify \
	--log-level error \
	--mount=type=devpts,destination=/dev/pts \
	--mount=type=bind,source=/tmp,destination=/tmp \
	--env=DBUS_SESSION_BUS_ADDRESS --env=DESKTOP_SESSION \
	--env=DISPLAY --env WAYLAND_DISPLAY --env=LANG \
	--env=XAUTHORITY --env=XDG_CURRENT_DESKTOP --env=XDG_DATA_DIRS \
	--env=XDG_MENU_PREFIX --env=XDG_RUNTIME_DIR --env=XDG_SESSION_CLASS \
	--env=XDG_SESSION_DESKTOP --env XDG_SESSION_TYPE --env=P11_KIT_SERVER_ADDRESS \
	--volume /dev:/dev:rslave \
	--volume /run/dbus/system_bus_socket:/run/dbus/system_bus_socket \
	--volume /run/user/${EUID}:/run/user/${EUID} \
	--volume /run/avahi-daemon/socket:/run/avahi-daemon/socket \
	--volume /run/media:/run/media:rslave \
	--volume "$HOME/.local/share/spotify:/root" \
	--volume "$XDG_DOWNLOAD_DIR:$XDG_DOWNLOAD_DIR:ro" \
	--volume "$XDG_MUSIC_DIR:$XDG_MUSIC_DIR:ro" \
	--volume "$XDG_PICTURES_DIR:$XDG_PICTURES_DIR:ro" \
	--volume "$XDG_VIDEOS_DIR:$XDG_VIDEOS_DIR:ro" \
	--security-opt=label=disable --user root:root \
	--cgroupns=host --ulimit=host --network=host --ipc=host --uts=host \
	tamado.codes/library/spotify:latest "$@"
EOF

	chmod +x "$HOME"/.local/bin/spotify
	echo "Created Spotify launcher script at $HOME/.local/bin/spotify"
}

create_desktop_file() {
	podman run --rm \
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
		--entrypoint '["/bin/bash", "-c"]' \
		--security-opt label=disable \
		--volume "$HOME/.local/share/icons/hicolor:/hicolor" \
		tamado.codes/library/spotify:latest \
		'rsync -rav --prune-empty-dirs --include="*/" --include="spotify-client.png" --exclude="*" /usr/share/icons/hicolor/* /hicolor'
}

main

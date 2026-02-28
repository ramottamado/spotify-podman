#!/bin/bash

set -ex

main() {
	echo "Starting Spotify setup script..."

	install_spotify
	create_wrapper
	create_desktop_file
	sync_icons

	echo "Spotify setup script completed successfully."
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
	--env=DBUS_SESSION_BUS_ADDRESS --env=DESKTOP_SESSION --env=DISPLAY --env=LANG \
	--env=SSH_AUTH_SOCK --env=XAUTHORITY --env=XDG_CURRENT_DESKTOP \
	--env=XDG_DATA_DIRS --env=XDG_MENU_PREFIX --env=XDG_RUNTIME_DIR --env=XDG_SESSION_CLASS \
	--env=XDG_SESSION_DESKTOP --env=XDG_SESSION_TYPE --env=P11_KIT_SERVER_ADDRESS \
	--volume /dev:/dev:rslave \
	--volume /run/dbus/system_bus_socket:/run/dbus/system_bus_socket \
	--volume /run/user/${EUID}:/run/user/${EUID} \
	--volume /run/avahi-daemon/socket:/run/avahi-daemon/socket \
	--volume /run/media:/run/media:rslave \
	--volume "$HOME/.local/share/spotify:/spotify" \
	--cgroupns=host --ipc=host --pid=host --security-opt=label=disable \
	--ulimit=host --userns=keep-id --network=host --pids-limit=2048 \
	--hostname "$(hostname)" \
	tamado.codes/library/spotify:latest "$@"
EOF

	chmod +x "$HOME"/.local/bin/spotify
	echo "Created Spotify launcher script at $HOME/.local/bin/spotify"
}

create_desktop_file() {
	podman run --rm \
		--entrypoint '["/bin/bash", "-c"]' \
		--security-opt label=disable \
		--userns keep-id \
		tamado.codes/library/spotify:latest \
		'sed -e "/^TryExec.*/d" -e "/^Exec.*/d" /usr/share/spotify/spotify.desktop' >/tmp/spotify.desktop

	if [ -f /tmp/spotify.desktop ]; then
		echo "Temporary Spotify desktop file created."
	else
		echo "Failed to create temporary Spotify desktop file. Exiting."
		exit 1
	fi

	echo "Exec=$(command -v gnome-session-inhibit) --app-id spotify --reason audio --inhibit suspend ${HOME}/.local/bin/spotify %U" >>/tmp/spotify.desktop
	cp -f /tmp/spotify.desktop "$HOME/.local/share/applications/spotify.desktop"
}

sync_icons() {
	echo "Syncing application icons..."
	podman run --rm \
		--entrypoint '["/bin/bash", "-c"]' \
		--security-opt label=disable \
		--volume "$HOME/.local/share/icons/hicolor:/hicolor" \
		--userns keep-id \
		tamado.codes/library/spotify:latest \
		'rsync -rav --prune-empty-dirs --include="*/" --include="spotify-client.png" --exclude="*" /usr/share/icons/hicolor/* /hicolor'
}

main

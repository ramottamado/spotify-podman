ROOT        := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
BUILD_DIR   := $(ROOT)/build
QUADLET_DIR := $(HOME)/.config/containers/systemd
SYSTEMD_DIR := $(HOME)/.config/systemd/user
BIN_DIR     := $(HOME)/.local/bin
APPS_DIR    := $(HOME)/.local/share/applications
DATA_DIR    := $(HOME)/.local/share/spotify
ICONS_DIR   := $(HOME)/.local/share/icons/hicolor

IMAGE       := tamado.codes/library/spotify:latest
BASE_IMAGE  := tamado.codes/library/ubuntu-spotify-base:26.04
BUILD_UNITS := spotify-base.build spotify.build

# Set BUILD=no to install without (re)building the images.
BUILD ?= yes

# Detect a toolbox container (toolbox creates /run/.toolboxenv). Override with
# IN_TOOLBOX=yes|no. Inside toolbox, podman and systemctl must act on the host
# (images, quadlets and the user systemd instance live there), so they are run
# through flatpak-spawn. $HOME is shared with the host, so file paths still match.
IN_TOOLBOX ?= $(if $(wildcard /run/.toolboxenv),yes,no)
export IN_TOOLBOX
HOST      := $(if $(filter yes,$(IN_TOOLBOX)),flatpak-spawn --host)
PODMAN    := $(HOST) podman
SYSTEMCTL := $(HOST) systemctl

PODMAN_ROOT_SHELL = $(PODMAN) run --rm --user 0 \
	--entrypoint '["/bin/bash", "-c"]' \
	--security-opt label=disable

.NOTPARALLEL:
.PHONY: all install quadlet build timer check-image launcher desktop icons uninstall clean

all: install

install: quadlet $(if $(filter yes,$(BUILD)),build) check-image launcher desktop icons timer
	@echo "Spotify setup completed successfully."

## Render the .build.in templates and install them plus the build context.
$(BUILD_DIR)/%.build: $(ROOT)/quadlet/%.build.in
	@mkdir -p $(BUILD_DIR)
	sed -E 's|%HOMEDIR%|$(HOME)|g' $< >$@

quadlet: $(addprefix $(BUILD_DIR)/,$(BUILD_UNITS))
	mkdir -p $(QUADLET_DIR)
	if $(PODMAN) quadlet list >/dev/null 2>&1; then \
		for f in $^; do $(PODMAN) quadlet install --replace --reload-systemd $$f || exit 1; done; \
	else \
		cp -p $^ $(QUADLET_DIR)/; \
	fi
	rm -rf $(QUADLET_DIR)/spotify
	cp -r $(ROOT)/image $(QUADLET_DIR)/spotify

## Build the base image, then the Spotify image (oneshot units; start blocks).
build: quadlet
	$(SYSTEMCTL) --user daemon-reload
	$(SYSTEMCTL) --user start spotify-base-build
	$(SYSTEMCTL) --user start spotify-build

## Weekly rebuild (picks up Spotify updates). Requires the quadlet units.
timer:
	install -Dm644 $(ROOT)/systemd/spotify-build.timer $(SYSTEMD_DIR)/spotify-build.timer
	$(SYSTEMCTL) --user daemon-reload
	$(SYSTEMCTL) --user enable --now spotify-build.timer

check-image:
	@$(PODMAN) image exists $(IMAGE) || { echo "Please build the Spotify image first (make build)."; exit 1; }

launcher:
	install -Dm755 $(ROOT)/bin/spotify $(BIN_DIR)/spotify
	mkdir -p $(DATA_DIR)
	@echo "Created Spotify launcher script at $(BIN_DIR)/spotify"

desktop: check-image
	@mkdir -p $(BUILD_DIR)
	$(PODMAN_ROOT_SHELL) $(IMAGE) \
		'sed -e "/^TryExec.*/d" -e "/^Exec.*/d" /usr/share/spotify/spotify.desktop' >$(BUILD_DIR)/spotify.desktop
	echo 'Exec=$(BIN_DIR)/spotify %U' >>$(BUILD_DIR)/spotify.desktop
	install -Dm644 $(BUILD_DIR)/spotify.desktop $(APPS_DIR)/spotify.desktop

icons: check-image
	mkdir -p $(ICONS_DIR)
	$(PODMAN_ROOT_SHELL) --volume $(ICONS_DIR):/hicolor $(IMAGE) \
		'rsync -rav --prune-empty-dirs --include="*/" --include="spotify-client.png" --exclude="*" /usr/share/icons/hicolor/* /hicolor'

## Remove everything install created. The running container (if any) is
## removed first so the images can be deleted.
uninstall:
	-$(SYSTEMCTL) --user disable --now spotify-build.timer
	rm -f $(SYSTEMD_DIR)/spotify-build.timer
	-$(PODMAN) container rm --force --ignore spotify
	$(PODMAN) image rm --ignore $(IMAGE) $(BASE_IMAGE)
	if $(PODMAN) quadlet list >/dev/null 2>&1; then \
		$(PODMAN) quadlet rm --ignore --reload-systemd $(BUILD_UNITS); \
	fi
	rm -f $(addprefix $(QUADLET_DIR)/,$(BUILD_UNITS))
	rm -rf $(QUADLET_DIR)/spotify
	-$(SYSTEMCTL) --user daemon-reload
	rm -f $(APPS_DIR)/spotify.desktop
	if [ -d $(ICONS_DIR) ]; then find $(ICONS_DIR) -name spotify-client.png -delete; fi
	rm -f $(BIN_DIR)/spotify
	@echo "Spotify uninstalled. Profile data in $(DATA_DIR) was kept."

clean:
	rm -rf $(BUILD_DIR)

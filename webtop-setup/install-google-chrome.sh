#!/usr/bin/env bash
#
# Installs Google Chrome inside the Webtop container.
#
# Invoked as root from .devcontainer/devcontainer.json (postStartCommand) via:
#   docker exec -u root webtop /webtop-setup/install-google-chrome.sh
#
# The container filesystem is disposable: it is rebuilt whenever the container is
# recreated, so this script is idempotent and simply checks for the binary each
# time instead of relying on a marker in /config.

set -euo pipefail

log() { printf '[webtop-setup] %s\n' "$*"; }

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# Google only publishes amd64 builds. On arm64 Codespaces we leave the image's
# bundled browser in place instead of failing the whole postStart hook.
if [ "$(uname -m)" != "x86_64" ]; then
  log "Skipping Google Chrome: no build for $(uname -m) (amd64 only)."
  exit 0
fi

if [ -x /opt/google/chrome/google-chrome ]; then
  log "Google Chrome already present: $(/opt/google/chrome/google-chrome --version 2>/dev/null || echo unknown)"
else
  log "Installing Google Chrome..."
  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl

  curl -fsSL -o /tmp/google-chrome.deb \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt-get install -y --no-install-recommends /tmp/google-chrome.deb

  rm -f /tmp/google-chrome.deb
  rm -rf /var/lib/apt/lists/*

  log "Installed $(/opt/google/chrome/google-chrome --version 2>/dev/null || echo 'Google Chrome')"
fi

# Chrome's namespace sandbox needs privileges this container does not have, so
# wrap the launcher. /usr/local/bin precedes /usr/bin on PATH, so terminal
# launches get the same flags as the menu entry.
log "Writing launcher wrapper..."
cat > /usr/local/bin/google-chrome-stable <<'WRAPPER'
#!/bin/sh
# Codespaces/Webtop: the container cannot provide Chrome's sandbox, and there is
# no keyring daemon to unlock, hence --no-sandbox and --password-store=basic.
exec /opt/google/chrome/google-chrome --no-sandbox --password-store=basic "$@"
WRAPPER
chmod 0755 /usr/local/bin/google-chrome-stable

# Desktop entries. Using the same file name as the .deb's entry means the
# per-user copy in /config overrides it, so there is only one menu item.
log "Writing desktop entries..."
APPS_DIR="/config/.local/share/applications"
DESKTOP_DIR="/config/Desktop"
mkdir -p "$APPS_DIR" "$DESKTOP_DIR"

cat > "$APPS_DIR/google-chrome.desktop" <<'DESKTOP'
[Desktop Entry]
Version=1.0
Name=Google Chrome
GenericName=Web Browser
Comment=Access the Internet
Exec=/usr/local/bin/google-chrome-stable %U
StartupNotify=true
Terminal=false
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=/usr/local/bin/google-chrome-stable

[Desktop Action new-private-window]
Name=New Incognito Window
Exec=/usr/local/bin/google-chrome-stable --incognito
DESKTOP

cp "$APPS_DIR/google-chrome.desktop" "$DESKTOP_DIR/google-chrome.desktop"
chmod 0755 "$DESKTOP_DIR/google-chrome.desktop"

# Keep the files owned by the desktop user (abc), otherwise XFCE cannot write
# to them and they may not appear in the menu.
chown "$PUID:$PGID" "$APPS_DIR" "$DESKTOP_DIR" \
  "$APPS_DIR/google-chrome.desktop" "$DESKTOP_DIR/google-chrome.desktop" 2>/dev/null || true

log "Google Chrome is ready."

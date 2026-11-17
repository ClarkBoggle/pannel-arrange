#!/usr/bin/env bash
# Uninstalls plasma-pannel: removes the copy made by install.sh and its
# translations, so Plasma uses its own panel again, and reloads the desktop.
# Popup sizes stay in the Plasma configuration.
set -euo pipefail

TARGET=$HOME/.local/share/plasma/plasmoids/org.kde.panel
OURS=contents/ui/PopupResize.qml
DOMAIN=plasma_applet_plasma-pannel

if [ -L "$TARGET" ] || [ -f "$TARGET/$OURS" ]; then
    rm -rf "$TARGET"
    rm -f "$HOME"/.local/share/locale/*/LC_MESSAGES/$DOMAIN.mo
    # Start limit of the service (3 per minute) reset: several installs in a row
    # would otherwise leave the desktop stopped
    systemctl --user reset-failed plasma-plasmashell 2> /dev/null || true
    systemctl --user restart plasma-plasmashell
    echo "Uninstalled: Plasma uses its own panel again (desktop reloaded)."
elif [ -e "$TARGET" ]; then
    echo "$TARGET is another copy of the panel package, not ours: left untouched." >&2
    exit 1
else
    echo "Not installed (nothing at $TARGET)."
fi

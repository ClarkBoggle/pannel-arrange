#!/usr/bin/env bash
# Installs pannel-arrange for the current user: copies our package to
# ~/.local/share/plasma/plasmoids/org.kde.panel (Plasma then uses it instead of
# the panel built into its plugin), copies Plasma's panel translations under
# our translation domain, and reloads the desktop. The system is never modified.
# Run it again after each change to package/.
# Uninstall: ./uninstall.sh
set -euo pipefail

TARGET=$HOME/.local/share/plasma/plasmoids/org.kde.panel
# File only found in our package: tells our installed copy from another one
OURS=contents/ui/PopupResize.qml
# Translation domain of our package: plasma_applet_ + its X-Plasma-RootPath
DOMAIN=plasma_applet_pannel-arrange
SYSTEM_DOMAIN=plasma_applet_org.kde.panel

cd "$(dirname "$0")"

# Another copy of the panel package (not ours): do not overwrite it
if [ -d "$TARGET" ] && [ ! -L "$TARGET" ] && [ ! -f "$TARGET/$OURS" ]; then
    echo "$TARGET holds another copy of the panel package: move it away first." >&2
    exit 1
fi

# A merge of a new Plasma version is not finished (conflicts): the package would
# break the panels
if git rev-parse --quiet --verify MERGE_HEAD > /dev/null || [ -n "$(git ls-files --unmerged)" ]; then
    echo "A merge is in progress: resolve the conflicts and commit first (see git status)." >&2
    exit 1
fi

# Plasma updated since our package was last merged with its panel: update first
# (update-plasma.sh merges the panel of the new version, then runs this script
# again)
version=$(plasmashell --version | awk '{ print $2 }')
if ! git rev-parse --quiet --verify "refs/tags/plasma-$version" > /dev/null; then
    echo "Plasma $version is not merged yet: running ./update-plasma.sh first."
    exec ./update-plasma.sh
fi

# Plasma's panel translations, under our domain (the panel strings are Plasma's)
for catalog in /usr/share/locale/*/LC_MESSAGES/$SYSTEM_DOMAIN.mo; do
    lang=$(basename "$(dirname "$(dirname "$catalog")")")
    mkdir -p "$HOME/.local/share/locale/$lang/LC_MESSAGES"
    cp "$catalog" "$HOME/.local/share/locale/$lang/LC_MESSAGES/$DOMAIN.mo"
done

# New copy next to the old one, then swapped (old copy or old link removed)
mkdir -p "$(dirname "$TARGET")"
rm -rf "$TARGET.new"
cp -r package "$TARGET.new"
rm -rf "$TARGET"
mv "$TARGET.new" "$TARGET"
echo "Installed in $TARGET"

# plasmashell started outside systemd (plasmashell --replace): stopped first,
# otherwise the service cannot start and the old code keeps running
if ! systemctl --user is-active --quiet plasma-plasmashell && pgrep -x plasmashell > /dev/null; then
    kquitapp6 plasmashell || true
    for _ in $(seq 1 20); do pgrep -x plasmashell > /dev/null || break; sleep 0.5; done
fi
# Start limit of the service (3 per minute) reset: several installs in a row
# would otherwise leave the desktop stopped
systemctl --user reset-failed plasma-plasmashell 2> /dev/null || true
systemctl --user restart plasma-plasmashell
echo "Desktop reloaded."

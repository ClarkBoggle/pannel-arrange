#!/usr/bin/env bash
# Updates our copy of the panel after a Plasma update.
#
# The panel of Plasma is built into a plugin: its source is taken from
# plasma-desktop, at the tag of the installed Plasma version
# (containments/panel), laid out as a package. The "upstream" branch holds it
# untouched, one Plasma version per commit. This script commits the panel of the
# installed version there, then merges it into the current branch: git thus
# applies our changes again on the new version, and reports the conflicts if
# there are any.
set -euo pipefail

# Reminder: the update is only local until pushed (the tag is moved, hence the +)
push_reminder() {
    echo "To publish this update (only if you can write to the repository):"
    echo "    git push origin main upstream +refs/tags/plasma-$version"
}

REPOSITORY=https://invent.kde.org/plasma/plasma-desktop.git

cd "$(dirname "$0")"

if [ -n "$(git status --porcelain)" ]; then
    echo "The repository has uncommitted changes: commit them first." >&2
    exit 1
fi

version=$(plasmashell --version | awk '{ print $2 }')

source=$(mktemp -d)
worktree=$(mktemp -d)
trap 'rm -rf "$source"; git worktree remove --force "$worktree"' EXIT

# 1. The panel source of this Plasma version (only containments/panel fetched)
echo "Fetching the panel of Plasma $version (plasma-desktop v$version)..."
git -C "$source" init --quiet
git -C "$source" remote add origin "$REPOSITORY"
git -C "$source" fetch --quiet --depth 1 --filter=blob:none origin tag "v$version"
git -C "$source" sparse-checkout set containments/panel
git -C "$source" checkout --quiet FETCH_HEAD
panel=$source/containments/panel

# 2. Laid out as a package and committed to the upstream branch (in a temporary
#    working tree, without touching the current branch)
# (fresh clone: only origin/upstream exists, the local branch is created from it)
if ! git rev-parse --quiet --verify refs/heads/upstream > /dev/null; then
    git branch --quiet --track upstream origin/upstream
fi
git worktree add --quiet "$worktree" upstream
rm -rf "$worktree/package"
mkdir -p "$worktree/package/contents/ui" "$worktree/package/contents/config"
cp "$panel"/*.qml "$panel"/*.js "$worktree/package/contents/ui/"
cp "$panel/main.xml" "$worktree/package/contents/config/"
cp "$panel/metadata.json" "$worktree/package/"
git -C "$worktree" add --all package

if git -C "$worktree" diff --cached --quiet; then
    echo "The panel has not changed since the last update: nothing to merge."
    # (a new Plasma version with the same panel is tagged too)
    git tag --force "plasma-$version" upstream > /dev/null
    ./install.sh
    push_reminder
    exit 0
fi
git -C "$worktree" commit --quiet -m "org.kde.panel containment of Plasma $version (plasma-desktop v$version, unmodified, laid out as a package)"
git tag --force "plasma-$version" upstream > /dev/null

# 3. Our changes applied again on the new version
if ! git merge --no-edit -m "Update to the panel of Plasma $version" upstream; then
    # The installed copy is made for the previous Plasma version: removed, so
    # that Plasma uses its own, up to date, panel until the conflicts are resolved
    echo
    echo "Conflicts between our changes and the new Plasma version." >&2
    ./uninstall.sh || true
    echo "Resolve the conflicts (see git status), then: git commit" >&2
    echo "then: ./install.sh" >&2
    push_reminder >&2
    exit 1
fi

# 4. Installed again
./install.sh
echo "Panel updated to Plasma $version."
push_reminder

#!/usr/bin/env bash
# Builds a release from the newest version in CHANGELOG.md:
#   build/Islet-<version>.zip, its SHA-256, and build/release-notes-<version>.md.
#
#   scripts/release.sh             # build and print what would be published
#   scripts/release.sh --publish   # also create the GitHub release (tag v<version>)
#
# The repository's visibility is not changed.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(sed -n 's/^## \([0-9][0-9.]*\).*/\1/p' CHANGELOG.md | head -1)}"
[ -n "$VERSION" ] || { echo "No version heading found in CHANGELOG.md" >&2; exit 1; }
NOTES="build/release-notes-$VERSION.md"
ZIP="build/Islet-$VERSION.zip"

if [ "${1:-}" = "--publish" ]; then
    git diff --quiet && git diff --cached --quiet || { echo "Commit your changes first." >&2; exit 1; }
    ! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || { echo "Tag v$VERSION already exists." >&2; exit 1; }
fi

VERSION="$VERSION" scripts/bundle.sh

mkdir -p build
awk -v v="$VERSION" 'index($0, "## " v) == 1 { f = 1; next } /^## / { f = 0 } f' CHANGELOG.md > "$NOTES"
[ -s "$NOTES" ] || { echo "CHANGELOG.md has no notes under ## $VERSION" >&2; exit 1; }

rm -f "$ZIP"
ditto -c -k --keepParent build/Islet.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
printf '\n---\n\n`Islet-%s.zip` SHA-256: `%s`\n' "$VERSION" "$SHA" >> "$NOTES"

echo "✓ $ZIP"
echo "  sha256 $SHA"
echo "  notes  $NOTES"

if [ "${1:-}" = "--publish" ]; then
    git push origin HEAD
    gh release create "v$VERSION" "$ZIP" --title "Islet $VERSION" --notes-file "$NOTES" --target "$(git rev-parse HEAD)"
fi

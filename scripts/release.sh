#!/usr/bin/env bash
# Builds a release from the newest version in CHANGELOG.md:
#   build/Islet-<version>.zip, build/Islet-<version>.zip.sha256 and build/release-notes-<version>.md.
#
#   scripts/release.sh                       # build, zip, check, and print what would be published
#   scripts/release.sh --publish             # also create the GitHub release (tag v<version>)
#   scripts/release.sh --no-build            # use the existing build/Islet.app (CI runs make app first)
#   scripts/release.sh --verify-zip <path>   # only the zip self-check, on a .zip or an .app; builds nothing
#
# Every zip is extracted twice, with ditto and with unzip, and the app's signature is checked in each
# copy; the release stops if either check fails. With SIGN_IDENTITY set (a Developer ID), the app is
# also notarised with the notarytool keychain profile NOTARY_PROFILE (default islet-notary), stapled,
# re-zipped, and must be accepted by Gatekeeper. --publish and --no-build also stop while the version's
# CHANGELOG heading says "unreleased" or its notes hold a placeholder line.
#
# The repository's visibility is not changed.
set -euo pipefail

usage() { grep '^#   scripts/' "$0" | sed 's/^#   //' >&2; exit 2; }

MODE="${1:-}"
case "$MODE" in
    "" | --publish | --no-build) ;;
    --verify-zip) [ -e "${2:-}" ] || usage; TARGET="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")" ;;
    *) usage ;;
esac
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
ZIP_OK=0
PARTIAL=""   # the zip this run is writing; set just before it is made
cleanup() {
    local rc=$?
    rm -rf "$WORK"
    # Never leave behind a zip that did not pass every check. An earlier run's zip is left alone.
    if [ "$rc" != 0 ] && [ "$ZIP_OK" = 0 ] && [ -n "$PARTIAL" ]; then rm -f "$PARTIAL" "$PARTIAL.sha256"; fi
}
trap cleanup EXIT

# Zips an app without resource forks or extended attributes. Their AppleDouble "._" entries
# become stray files when the zip is extracted with command-line unzip, which breaks the seal.
make_zip() {  # <app> <zip>
    rm -f "$2"
    ditto -c -k --norsrc --noextattr --keepParent "$1" "$2"
}

# Extracts a zip with ditto and with unzip, and checks every app's signature in both copies.
verify_zip() {  # <zip>
    local zip="$1" ok=1 tool dir app
    # Not grep -q: it stops reading early, and under pipefail zipinfo's SIGPIPE hides the match.
    if zipinfo -1 "$zip" | grep -E '(^|/)\._' >/dev/null; then
        echo "error: $(basename "$zip") contains AppleDouble (._) entries" >&2
        ok=0
    fi
    for tool in ditto unzip; do
        dir="$WORK/$tool"
        rm -rf "$dir" && mkdir -p "$dir"
        if [ "$tool" = ditto ]; then ditto -x -k "$zip" "$dir" || ok=0
        else /usr/bin/unzip -q "$zip" -d "$dir" || ok=0
        fi
        for app in "$dir"/*.app; do
            if [ ! -d "$app" ]; then
                echo "error: no .app in $(basename "$zip") after extracting with $tool" >&2
                ok=0
            elif codesign --verify --strict --deep "$app" 2>"$WORK/codesign.log"; then
                echo "  ✓ $(basename "$app") signature intact after extracting with $tool"
            else
                echo "error: $(basename "$app") fails codesign --verify --strict after extracting with $tool:" >&2
                sed 's/^/    /' "$WORK/codesign.log" >&2
                ok=0
            fi
        done
    done
    [ "$ok" = 1 ]
}

if [ "$MODE" = --verify-zip ]; then
    if [ -d "$TARGET" ]; then
        make_zip "$TARGET" "$WORK/check.zip"
        TARGET="$WORK/check.zip"
    fi
    verify_zip "$TARGET" || { echo "Zip self-check failed." >&2; exit 1; }
    echo "✓ zip self-check passed"
    exit 0
fi

VERSION="${VERSION:-$(sed -n 's/^## \([0-9][0-9.]*\).*/\1/p' CHANGELOG.md | head -1)}"
[ -n "$VERSION" ] || { echo "No version heading found in CHANGELOG.md" >&2; exit 1; }
APP="build/Islet.app"
NOTES="build/release-notes-$VERSION.md"
ZIP="build/Islet-$VERSION.zip"

if [ "$MODE" = --publish ]; then
    git diff --quiet && git diff --cached --quiet || { echo "Commit your changes first." >&2; exit 1; }
    ! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || { echo "Tag v$VERSION already exists." >&2; exit 1; }
fi

mkdir -p build
awk -v v="$VERSION" '$0 == "## " v || index($0, "## " v " ") == 1 { f = 1; next } /^## / { f = 0 } f' CHANGELOG.md > "$NOTES"
[ -s "$NOTES" ] || { echo "CHANGELOG.md has no notes under ## $VERSION" >&2; exit 1; }

# The notes go out as they are, so an "(unreleased)" heading or a leftover placeholder line
# (such as MEASURED_TABLE) stops a real release. A plain dry run only warns.
HEADING="$(awk -v v="$VERSION" '$0 == "## " v || index($0, "## " v " ") == 1 { print; exit }' CHANGELOG.md)"
NOT_READY=""
case "$HEADING" in *[Uu]nreleased*) NOT_READY="CHANGELOG.md still says \"$HEADING\"; give it the release date." ;; esac
PLACEHOLDERS="$(grep -E '^[A-Z][A-Z0-9]*_[A-Z0-9_]+$' "$NOTES" | tr '\n' ' ' || true)"
[ -z "$PLACEHOLDERS" ] || NOT_READY="${NOT_READY:+$NOT_READY }The notes for $VERSION still contain placeholder lines: ${PLACEHOLDERS% }."
if [ -n "$NOT_READY" ]; then
    if [ -z "$MODE" ]; then echo "warning: $NOT_READY" >&2
    else echo "Release stopped: $NOT_READY" >&2; exit 1
    fi
fi

[ "$MODE" = --no-build ] || VERSION="$VERSION" scripts/bundle.sh
[ -d "$APP" ] || { echo "No $APP. Run make app first." >&2; exit 1; }
APP_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
[ "$APP_VERSION" = "$VERSION" ] || { echo "$APP is version $APP_VERSION, not $VERSION." >&2; exit 1; }

STOP="Release stopped: the zip self-check failed."
echo "▸ zipping and checking $ZIP"
PARTIAL="$ZIP"
make_zip "$APP" "$ZIP"
verify_zip "$ZIP" || { echo "$STOP" >&2; exit 1; }

if [ -n "${SIGN_IDENTITY:-}" ]; then
    PROFILE="${NOTARY_PROFILE:-islet-notary}"
    echo "▸ notarising with keychain profile $PROFILE"
    xcrun notarytool submit "$ZIP" --wait --keychain-profile "$PROFILE"
    # Whatever notarytool's exit status, a rejected submission has no ticket, so stapler fails.
    xcrun stapler staple "$APP" || { echo "Release stopped: Apple issued no notarisation ticket (xcrun notarytool log <id> explains why)." >&2; exit 1; }
    spctl -a -vv "$APP" || { echo "Release stopped: Gatekeeper does not accept $APP." >&2; exit 1; }
    echo "▸ re-zipping the stapled app"
    make_zip "$APP" "$ZIP"
    verify_zip "$ZIP" || { echo "$STOP" >&2; exit 1; }
else
    echo "Not notarised: macOS will ask users to confirm the first launch (see README)"
fi

ZIP_OK=1
(cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
SHA="$(cut -d' ' -f1 "$ZIP.sha256")"
printf '\n---\n\n`Islet-%s.zip` SHA-256: `%s`\n' "$VERSION" "$SHA" >> "$NOTES"

echo "✓ $ZIP"
echo "  sha256 $SHA ($ZIP.sha256)"
echo "  notes  $NOTES"

if [ "$MODE" = --publish ]; then
    git push origin HEAD
    gh release create "v$VERSION" "$ZIP" "$ZIP.sha256" --title "Islet $VERSION" --notes-file "$NOTES" --target "$(git rev-parse HEAD)"
fi

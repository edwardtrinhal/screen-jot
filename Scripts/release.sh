#!/bin/bash
# Cuts a GitHub release for the version in VERSION:
#   builds the DMG, tags v<version>, uploads the DMG as "ScreenJot.dmg" (stable
#   /releases/latest/download/ScreenJot.dmg URL) and as the versioned file.
# Release notes come from the matching "## <version>" section of CHANGELOG.md.
# Env: SKIP_BUILD=1 to reuse build/ScreenJot-<version>.dmg, DRAFT=1 for a draft release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' < VERSION)
TAG="v$VERSION"
DMG="build/ScreenJot-$VERSION.dmg"

if [ -n "$(git status --porcelain)" ]; then
    echo "✗ Working tree is dirty; commit first." >&2; exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "✗ Tag $TAG already exists. Bump VERSION first." >&2; exit 1
fi

NOTES=$(awk -v v="$VERSION" '
    /^## / { on = ($2 == v) ; next }
    on { print }
' CHANGELOG.md | sed -e '/./,$!d')
if [ -z "$NOTES" ]; then
    echo "✗ No \"## $VERSION\" section in CHANGELOG.md." >&2; exit 1
fi

[ "${SKIP_BUILD:-0}" = "1" ] || Scripts/make-dmg.sh
[ -f "$DMG" ] || { echo "✗ $DMG not found" >&2; exit 1; }

cp "$DMG" build/ScreenJot.dmg

echo "▸ Tagging $TAG"
git tag -a "$TAG" -m "ScreenJot $VERSION"
git push origin HEAD "$TAG"

echo "▸ Creating GitHub release"
ARGS=(--title "ScreenJot $VERSION" --notes "$NOTES")
[ "${DRAFT:-0}" = "1" ] && ARGS+=(--draft)
gh release create "$TAG" "${ARGS[@]}" build/ScreenJot.dmg "$DMG"
rm -f build/ScreenJot.dmg
echo "✓ $(gh release view "$TAG" --json url -q .url)"

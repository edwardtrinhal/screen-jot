#!/bin/bash
# Cuts a GitHub release.
#   Scripts/release.sh            release the version already in VERSION (needs a "## <version>" in CHANGELOG.md)
#   Scripts/release.sh patch      bump 0.1.1 → 0.1.2, then release   (also: minor, major, or an explicit X.Y.Z)
# A bump writes VERSION, adds a CHANGELOG.md section from the commit subjects since the last tag,
# and commits "Bump version to X.Y.Z". Edit CHANGELOG.md beforehand if you want nicer notes.
# Then: builds the DMG, tags v<version>, pushes, uploads the DMG as "ScreenJot.dmg" (stable
# /releases/latest/download/ScreenJot.dmg URL) and as the versioned file.
# Env: SKIP_BUILD=1 to reuse build/ScreenJot-<version>.dmg, DRAFT=1 for a draft release.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain)" ]; then
    echo "✗ Working tree is dirty; commit first." >&2; exit 1
fi

CURRENT=$(tr -d '[:space:]' < VERSION)
BUMP="${1:-}"

if [ -n "$BUMP" ]; then
    IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"
    case "$BUMP" in
        major) VERSION="$((MAJOR + 1)).0.0" ;;
        minor) VERSION="$MAJOR.$((MINOR + 1)).0" ;;
        patch) VERSION="$MAJOR.$MINOR.$((${PATCH:-0} + 1))" ;;
        [0-9]*.[0-9]*.[0-9]*) VERSION="$BUMP" ;;
        *) echo "✗ Usage: $0 [patch|minor|major|X.Y.Z]" >&2; exit 1 ;;
    esac
    if [ "$VERSION" = "$CURRENT" ]; then
        echo "✗ VERSION is already $VERSION." >&2; exit 1
    fi
    if grep -q "^## $VERSION\$" CHANGELOG.md; then
        echo "✗ CHANGELOG.md already has a \"## $VERSION\" section." >&2; exit 1
    fi

    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
    RANGE=${LAST_TAG:+$LAST_TAG..HEAD}
    BULLETS=$(git log --no-merges --format='- %s' $RANGE | grep -v -i '^- bump version' || true)
    [ -n "$BULLETS" ] || BULLETS="- Maintenance release"

    echo "▸ Bumping $CURRENT → $VERSION"
    printf '%s\n' "$VERSION" > VERSION
    {
        echo "# Changelog"
        echo
        echo "## $VERSION"
        echo
        echo "$BULLETS"
        echo
        tail -n +3 CHANGELOG.md
    } > CHANGELOG.md.new
    mv CHANGELOG.md.new CHANGELOG.md
    git add VERSION CHANGELOG.md
    git commit -q -m "Bump version to $VERSION"
    echo "$BULLETS" | sed 's/^/    /'
else
    VERSION="$CURRENT"
fi

TAG="v$VERSION"
DMG="build/ScreenJot-$VERSION.dmg"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "✗ Tag $TAG already exists. Run with 'patch' (or minor/major) to bump." >&2; exit 1
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

#!/usr/bin/env bash
set -euo pipefail

VERSION_FORM='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[A-Za-z][0-9A-Za-z-]*\.(0|[1-9][0-9]*))?$'
VERSION_LINE='^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"[^"]*"'

usage() {
    cat >&2 <<'TEXT'
usage: bash scripts/set-package-version.sh [--dry-run] <version>

Writes the version into the one Packages/<Name>/package.json of the repository, run from its root by the
release and by nothing else. The version is MAJOR.MINOR.PATCH with an optional -<prerelease>.<N>. The
"version" line is rewritten by text match, keeping its indentation and the file's line endings, and the
script prints "succeeded: <package> <old> -> <new>". --dry-run prints "previewed:" and writes nothing.
TEXT
}

stop() {
    printf 'failed: %s\n' "$*" >&2
    exit 1
}

dry_run="false"
version=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run="true"; shift ;;
        -*) usage; exit 2 ;;
        *)
            [ -z "$version" ] || { usage; exit 2; }
            version="$1"
            shift
            ;;
    esac
done
[ -n "$version" ] || { usage; exit 2; }

printf '%s\n' "$version" | grep -Eq "$VERSION_FORM" \
    || stop "the version '$version' is not MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-<prerelease>.<N>"

manifests=""
count=0
for candidate in Packages/*/package.json; do
    [ -f "$candidate" ] || continue
    manifests="$manifests${manifests:+, }$candidate"
    count=$((count + 1))
    manifest="$candidate"
done
[ "$count" -gt 0 ] || stop "no Packages/<Name>/package.json under $(pwd)"
[ "$count" -eq 1 ] || stop "the repository holds $count packages, and the release writes one: $manifests"

lines="$(grep -Ec "$VERSION_LINE" "$manifest" || true)"
[ "$lines" -eq 1 ] || stop "$manifest holds $lines \"version\" lines, and the release rewrites exactly one"

package="$(sed -n 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)"
[ -n "$package" ] || package="$manifest"
old="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest")"

if [ "$dry_run" = "true" ]; then
    printf 'previewed: %s %s -> %s in %s, nothing written\n' "$package" "$old" "$version" "$manifest"
    exit 0
fi

rewritten="$(mktemp)"
trap 'rm -f "$rewritten"' EXIT
version_pattern='^([[:space:]]*"version"[[:space:]]*:[[:space:]]*")[^"]*(".*)$'
while true; do
    ending=$'\n'
    if ! IFS= read -r line; then
        [ -n "$line" ] || break
        ending=""
    fi
    if [[ "$line" =~ $version_pattern ]]; then
        line="${BASH_REMATCH[1]}$version${BASH_REMATCH[2]}"
    fi
    printf '%s%s' "$line" "$ending"
    [ -n "$ending" ] || break
done < "$manifest" > "$rewritten"
cat "$rewritten" > "$manifest"
printf 'succeeded: %s %s -> %s\n' "$package" "$old" "$version"

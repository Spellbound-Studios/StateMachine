#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo 'usage: bash scripts/initialise-package.sh <Name> "<sentence>" [--kind library|tool] [--requires a,b,c] [--presentation] [--core-range "<range>"]' >&2
}

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [ "$#" -lt 2 ]; then
    usage
    exit 2
fi

name="$1"
sentence="$2"
shift 2

kind="library"
requires=""
presentation="false"
core_range="[1.1.9,3.0.0)"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --kind) kind="${2:-}"; shift 2 ;;
        --requires) requires="${2:-}"; shift 2 ;;
        --presentation) presentation="true"; shift ;;
        --core-range) core_range="${2:-}"; shift 2 ;;
        *) usage; exit 2 ;;
    esac
done

if [ ! -d "Packages/PackageName" ]; then
    echo "Packages/PackageName does not exist: this repository is already initialised" >&2
    exit 2
fi

if ! printf '%s' "$name" | grep -Eq '^[A-Z][A-Za-z0-9]*$'; then
    echo "The name must start with an upper-case letter and contain only letters and digits: $name" >&2
    exit 2
fi

if [ "$kind" != "library" ] && [ "$kind" != "tool" ]; then
    echo "The kind must be library or tool: $kind" >&2
    exit 2
fi

if [ "$kind" = "tool" ] && [ "$presentation" = "true" ]; then
    echo "A tool has no runtime, so it cannot carry a presentation assembly" >&2
    exit 2
fi

lower="$(printf '%s' "$name" | tr 'A-Z' 'a-z')"

dependency_lines=""
if [ -n "$requires" ]; then
    IFS=',' read -r -a requested <<< "$requires"
    for item in "${requested[@]}"; do
        case "$item" in
            burst) id="com.unity.burst" ;;
            mathematics) id="com.unity.mathematics" ;;
            collections) id="com.unity.collections" ;;
            urp) id="com.unity.render-pipelines.universal" ;;
            inputsystem) id="com.unity.inputsystem" ;;
            *) echo "Unknown requirement: $item. Allowed: burst, mathematics, collections, urp, inputsystem" >&2; exit 2 ;;
        esac
        version="$(awk -F '\t' -v wanted="$id" '$1 == wanted { gsub(/\r/, "", $2); print $2 }' managed-unity-packages.txt)"
        if [ -z "$version" ]; then
            echo "No version for $id in managed-unity-packages.txt" >&2
            exit 2
        fi
        dependency_lines="${dependency_lines}${id}=${version}"$'\n'
    done
fi

core_address="$(sed -nE 's/^[[:space:]]*"com\.spellboundstudios\.core": "([^"]+)".*$/\1/p' Packages/manifest.json | tr -d '\r')"
if [ -z "$core_address" ]; then
    echo "Packages/manifest.json holds no line for com.spellboundstudios.core" >&2
    exit 2
fi

mv "Packages/PackageName" "Packages/$name"
echo "Renamed Packages/PackageName to Packages/$name"

while IFS= read -r path; do
    directory="$(dirname "$path")"
    base="$(basename "$path")"
    mv "$path" "$directory/${base//PackageName/$name}"
    echo "Renamed $path"
done < <(find "Packages/$name" -depth -name '*PackageName*')

backslash="$(printf '\134')"
escaped_sentence="$(printf '%s' "$sentence" | sed "s/[&|$backslash]/$backslash$backslash&/g")"
escaped_address="$(printf '%s' "$core_address" | sed "s/[&|$backslash]/$backslash$backslash&/g")"
targets=".releaserc.yaml AGENTS.md Packages/$name Packages/manifest.json"
while IFS= read -r file; do
    sed -i "s|PackageName|$name|g; s|packagename|$lower|g; s|PACKAGE_SENTENCE|$escaped_sentence|g; s|CORE_RANGE|$core_range|g; s|FOUNDATION_ADDRESS|$escaped_address|g" "$file"
    echo "Filled $file"
done < <(grep -rIl -e PackageName -e packagename -e PACKAGE_SENTENCE -e CORE_RANGE -e FOUNDATION_ADDRESS --exclude-dir=.git $targets || true)

if [ "$kind" = "tool" ]; then
    mv "Packages/$name/Runtime/${name}Kit.cs" "Packages/$name/Editor/${name}Kit.cs"
    rm -rf "Packages/$name/Runtime" "Packages/$name/Runtime.meta" "Packages/$name/Tests/Runtime" "Packages/$name/Tests/Runtime.meta"
    sed -i 's|"references": \[[^]]*\]|"references": ["Spellbound.Core"]|' "Packages/$name/Editor/Spellbound.$name.Editor.asmdef"
    sed -i "s|\"references\": \[[^]]*\]|\"references\": [\"Spellbound.$name.Editor\", \"UnityEngine.TestRunner\", \"UnityEditor.TestRunner\"]|" "Packages/$name/Tests/Editor/Spellbound.$name.Editor.Tests.asmdef"
    sed -i "s|\"references\": \[[^]]*\]|\"references\": [\"Spellbound.$name.Editor\"]|" "Packages/$name/Samples~/${name}Sample/Spellbound.$name.Samples.asmdef"
    sed -i 's|"includePlatforms": \[\]|"includePlatforms": ["Editor"]|' "Packages/$name/Samples~/${name}Sample/Spellbound.$name.Samples.asmdef"
    echo "Moved the front door into the editor assembly and removed the runtime assembly and its tests for a tool"
fi

if [ -n "$dependency_lines" ]; then
    block=""
    while IFS='=' read -r id version; do
        [ -z "$id" ] && continue
        block="${block}    \"$id\": \"$version\","$'\n'
    done <<< "$dependency_lines"
    package_file="Packages/$name/package.json"
    awk -v block="${block%,$'\n'}" '
        /^  "dependencies": \{\},?$/ { print "  \"dependencies\": {"; print block; print "  },"; next }
        { print }
    ' "$package_file" > "$package_file.tmp"
    mv "$package_file.tmp" "$package_file"
    awk -v block="$block" '
        { print }
        /^  "dependencies": \{$/ { printf "%s", block }
    ' Packages/manifest.json > Packages/manifest.json.tmp
    mv Packages/manifest.json.tmp Packages/manifest.json
    echo "Added dependencies to package.json and Packages/manifest.json"
fi

if [ "$presentation" = "true" ]; then
    presentation_directory="Packages/$name/Runtime/Presentation"
    mkdir -p "$presentation_directory"
    cat > "$presentation_directory/Spellbound.$name.Presentation.asmdef" <<ASMDEF
{
  "name": "Spellbound.$name.Presentation",
  "rootNamespace": "Spellbound.$name.Presentation",
  "references": ["Spellbound.$name", "Spellbound.Core"],
  "includePlatforms": [],
  "excludePlatforms": [],
  "allowUnsafeCode": false,
  "overrideReferences": false,
  "precompiledReferences": [],
  "autoReferenced": true,
  "defineConstraints": ["SPELLBOUND_CORE", "!UNITY_SERVER"],
  "versionDefines": [
    {
      "name": "com.spellboundstudios.core",
      "expression": "$core_range",
      "define": "SPELLBOUND_CORE"
    }
  ],
  "noEngineReferences": false
}
ASMDEF
    echo "Created $presentation_directory/Spellbound.$name.Presentation.asmdef"
fi

echo "Initialised $name"
rm -- "$0"
echo "Removed scripts/initialise-package.sh"

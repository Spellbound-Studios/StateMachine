#!/usr/bin/env bash
set -uo pipefail

RULES=(I2 I4 I5 I8 D5 D6 C13 P2 V1 V2 V6 A3 S1)
TEMPLATE_CHECKS=(organisation studio-package version line-text-pointer line-endings)

NAME_PREFIX="${NAME_PREFIX-Spellbound.}"
IDENTIFIER_PREFIX="${IDENTIFIER_PREFIX-com.spellboundstudios.}"
FLOOR="${FLOOR-6000.3}"
ORGANISATION="${ORGANISATION-Spellbound-Studios}"
OLD_ORGANISATION="${OLD_ORGANISATION-Spell-Bound-Studios}"
STUDIO_PACKAGE_PATTERN="${STUDIO_PACKAGE_PATTERN-Packages/Studio*}"
LINE_TEXT_ADDRESS="${LINE_TEXT_ADDRESS-https://github.com/Spellbound-Studios/.github/tree/main/line}"
FOUNDATION_PACKAGE="${FOUNDATION_PACKAGE-com.spellboundstudios.core}"
FOUNDATION_APPDOMAIN_TYPES="${FOUNDATION_APPDOMAIN_TYPES-Spellbound.Core.Tooling.AssemblyScanning \
Spellbound.Core.Logging.FileSink}"
MAINTAINER_FILES="${MAINTAINER_FILES-CLAUDE.md claude.md .claude}"
TEST_ASSEMBLIES="${TEST_ASSEMBLIES-UnityEngine.TestRunner UnityEditor.TestRunner Unity.PerformanceTesting \
Unity.UI.TestFramework.Runtime Unity.UI.TestFramework.Editor}"
SCAFFOLD_FOLDER="${SCAFFOLD_FOLDER-Assets/_Project}"
NEVER_CONTENT_FOLDERS="${NEVER_CONTENT_FOLDERS-Library Temp Logs obj UserSettings}"
VERSION_BASE_FOLDER="${VERSION_BASE_FOLDER-}"

export LC_ALL=C

never_content=()
for folder in $NEVER_CONTENT_FOLDERS; do
    [ "${#never_content[@]}" -eq 0 ] || never_content+=(-o)
    never_content+=(-name "$folder")
done
[ "${#never_content[@]}" -gt 0 ] || never_content=(-name "")
project_content=()

usage() {
    cat >&2 <<'TEXT'
usage: bash scripts/check.sh [--rule <id>] [root]

Runs the line rules that are a text match over every Packages/<Name>/package.json under the root, then the
template's own checks. Each finding prints as "failed: <rule> <file>[:<line>] <message>"; the last line says
how many rules and template checks ran, or how many findings failed them. --rule runs one rule or check.
The settings at the top of the script read an environment variable of the same name first.
TEXT
}

script_folder="$(cd "$(dirname "$0")" && pwd)"
root_argument="$script_folder/.."
only=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --rule)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            only="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        -*) usage; exit 2 ;;
        *) root_argument="$1"; shift ;;
    esac
done

if [ -n "$only" ]; then
    case " ${RULES[*]} ${TEMPLATE_CHECKS[*]} " in
        *" $only "*) ;;
        *)
            echo "unknown rule: $only. The rules are ${RULES[*]}; the template checks are ${TEMPLATE_CHECKS[*]}" >&2
            exit 2
            ;;
    esac
fi

root="$(cd "$root_argument" 2>/dev/null && pwd)" || { echo "not a folder: $root_argument" >&2; exit 2; }
cd "$root" || exit 2

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

COMMON_AWK='
function fail(location, message) { print "failed: " rule " " location " " message }
function at(path, line) { return line > 0 ? path ":" line : path }
function trim(text) { sub(/^[ \t]+/, "", text); sub(/[ \t]+$/, "", text); return text }
function plain(text) { sub(/\r$/, "", text); if (index(text, "\357\273\277") == 1) text = substr(text, 4); return text }
'

FIELDS_AWK='
function name_here() { return kind[depth] == "[" ? count[depth] : key }
{ text = text plain($0) "\n" }
END {
    total = length(text); line = 1; depth = 0; key = ""; after_colon = 0
    for (i = 1; i <= total; i++) {
        c = substr(text, i, 1)
        if (c == "\n") { line++; continue }
        if (c == "\"") {
            value = ""; start = line
            for (j = i + 1; j <= total; j++) {
                d = substr(text, j, 1)
                if (d == "\\") { j++; value = value substr(text, j, 1); continue }
                if (d == "\"") break
                if (d == "\n") line++
                value = value d
            }
            i = j
            if (kind[depth] == "{" && !after_colon) { key = value; continue }
            print "s\t" path[depth] "/" name_here() "\t" value "\t" start
            after_colon = 0
            continue
        }
        if (c == ":") { after_colon = 1; continue }
        if (c == "{" || c == "[") {
            child = depth == 0 ? "" : path[depth] "/" name_here()
            depth++; kind[depth] = c; path[depth] = child; count[depth] = 0; after_colon = 0
            print "c\t" child "\t" c "\t" line
            continue
        }
        if (c == "}" || c == "]") { if (depth > 0) depth--; after_colon = 0; continue }
        if (c == ",") { after_colon = 0; if (kind[depth] == "[") count[depth]++; continue }
    }
}
'

MASK_AWK='
function mask(source,    out, i, n, c, d) {
    out = ""; n = length(source); i = 1
    while (i <= n) {
        c = substr(source, i, 1); d = substr(source, i + 1, 1)
        if (in_comment) {
            if (c == "*" && d == "/") { in_comment = 0; out = out "  "; i += 2 } else { out = out " "; i++ }
            continue
        }
        if (in_verbatim) {
            if (c == "\"" && d == "\"") { out = out "  "; i += 2; continue }
            if (c == "\"") in_verbatim = 0
            out = out " "; i++
            continue
        }
        if (c == "/" && d == "/") { while (i <= n) { out = out " "; i++ }; break }
        if (c == "/" && d == "*") { in_comment = 1; out = out "  "; i += 2; continue }
        if ((c == "@" && d == "\"") ||
            ((c == "@" || c == "$") && (d == "@" || d == "$") && substr(source, i + 2, 1) == "\"")) {
            in_verbatim = 1
            while (substr(source, i, 1) != "\"") { out = out " "; i++ }
            out = out " "; i++
            continue
        }
        if (c == "\"" || c == "'\''") {
            out = out " "; i++
            while (i <= n) {
                d = substr(source, i, 1)
                if (d == "\\") { out = out "  "; i += 2; continue }
                out = out " "; i++
                if (d == c) break
            }
            continue
        }
        out = out c; i++
    }
    return out
}
function words_of(code, word,    count, rest, pattern) {
    count = 0; rest = " " code " "
    pattern = "[^A-Za-z0-9_]" word (word ~ /[A-Za-z0-9_]$/ ? "[^A-Za-z0-9_]" : "")
    while (match(rest, pattern)) {
        count++; rest = substr(rest, RSTART + RLENGTH - 1)
    }
    return count
}
'

finding_count=0
rules_run=0
checks_run=0

report() {
    local output="$1" name="$2" status="$3" failed
    failed="$(printf '%s\n' "$output" | grep -c '^failed: ' || true)"
    if [ "$status" -ne 0 ] && [ "$failed" -eq 0 ]; then
        output="${output:+$output$'\n'}failed: $name the rule itself failed (exit $status)"
        failed=1
    fi
    [ -n "$output" ] || return 0
    printf '%s\n' "$output"
    finding_count=$((finding_count + failed))
}

read_fields() {
    awk "$COMMON_AWK$FIELDS_AWK" "$1"
}

field() {
    awk -F '\t' -v wanted="$2" '$1 == "s" && $2 == wanted { print $3; exit }' "$1"
}

field_line() {
    awk -F '\t' -v wanted="$2" '
        $1 == "s" && $2 == wanted { print $4; found = 1; exit }
        END { if (!found) print 1 }' "$1"
}

list_package() {
    (
        cd "$package_folder" || exit 1
        hidden='( -name .git -o -name *~ ! -name Samples~ ! -name Documentation~ )'
        set -f
        find . $hidden -prune -type f -print -o -type f -print | sed 's|^\./||' | sort > "$work/files"
        find . ! -name . $hidden -prune -type d -print -o ! -name . -type d -print \
            | sed 's|^\./||' | sort > "$work/folders"
        find . -name .git -prune -print | sed 's|^\./||' >> "$work/folders"
    )
}

read_assemblies() {
    : > "$work/assemblies"
    : > "$work/references"
    : > "$work/claims"
    local definition order=0
    while IFS= read -r definition; do
        read_fields "$package_folder/$definition" > "$work/definition.fields"
        local guid=""
        [ -f "$package_folder/$definition.meta" ] && guid="$(sed -n 's/^guid: *\([0-9a-fA-F]*\).*/\1/p' \
            "$package_folder/$definition.meta" | tr -d '\r' | head -n 1)"
        awk -F '\t' -v definition="$definition" -v guid="$guid" -v tests=" $TEST_ASSEMBLIES " '
            $1 == "s" && $2 == "/name" && name == "" { name = $3; name_line = $4 }
            $1 == "s" && $2 == "/rootNamespace" { root_namespace = $3; root_namespace_line = $4 }
            $1 == "s" && $2 ~ /^\/references\// { if (index(tests, " " $3 " ")) test = 1 }
            $1 == "s" && $2 ~ /^\/defineConstraints\// { if ($3 == "UNITY_INCLUDE_TESTS") test = 1 }
            $1 == "s" && $2 ~ /^\/includePlatforms\// { platforms++; if ($3 == "Editor") editor_platform = 1 }
            END {
                folder = definition; sub(/\/?[^\/]*$/, "", folder)
                if (substr(folder "/", 1, 6) == "Tests/") test = 1
                sample = substr(folder "/", 1, 9) == "Samples~/"
                bootstrap = substr(folder "/", 1, 10) == "Bootstrap/" || name ~ /\.Bootstrap$/
                editor = (platforms == 1 && editor_platform) || name ~ /\.Editor$/ || index(name, ".Editor.") > 0
                if (name_line == "") name_line = 1
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%s\n", definition, folder, name, name_line,
                    root_namespace, root_namespace_line, test, sample, bootstrap, editor, guid
            }' "$work/definition.fields" >> "$work/assemblies"
        awk -F '\t' -v definition="$definition" '
            $1 == "s" && $2 ~ /^\/references\// { print definition "\t" $3 "\t" $4 }' \
            "$work/definition.fields" >> "$work/references"
        order=$((order + 1))
    done < <(grep '\.asmdef$' "$work/files")
    while IFS=$'\t' read -r definition folder rest; do
        order=$((order + 1))
        printf '%s\t%s\t%s\n' "$folder" "$definition" "$order" >> "$work/claims"
    done < "$work/assemblies"
    while IFS= read -r reference; do
        order=$((order + 1))
        local target
        target="$(read_fields "$package_folder/$reference" \
            | awk -F '\t' '$1 == "s" && $2 == "/reference" { print $3; exit }')"
        local owner
        owner="$(awk -F '\t' -v target="$target" '
            target ~ /^GUID:/ { if (tolower(substr(target, 6)) == tolower($11) && $11 != "") { print $1; exit } next }
            $3 == target && target != "" { print $1; exit }' "$work/assemblies")"
        local folder="${reference%/*}"
        [ "$folder" = "$reference" ] && folder=""
        printf '%s\t%s\t%s\n' "$folder" "${owner:--}" "$order" >> "$work/claims"
    done < <(grep '\.asmref$' "$work/files")
    awk -F '\t' '
        FILENAME == ARGV[1] { claim_folder[++claims] = $1; claim_owner[claims] = $2; claim_order[claims] = $3; next }
        FILENAME == ARGV[2] { row[$1] = $0; next }
        /\.cs$/ {
            best = 0
            for (k = 1; k <= claims; k++) {
                if (claim_folder[k] == "" || index($0, claim_folder[k] "/") == 1) {
                    if (best == 0 || length(claim_folder[k]) > length(claim_folder[best]) ||
                        (length(claim_folder[k]) == length(claim_folder[best]) &&
                        claim_order[k] + 0 < claim_order[best] + 0))
                        best = k
                }
            }
            if (best > 0 && claim_owner[best] != "-") print $0 "\t" row[claim_owner[best]]
        }' "$work/claims" "$work/assemblies" "$work/files" > "$work/sources"
}

rule_I2() {
    awk -F '\t' -v rule=I2 -v package="$package_path" -v name="$package_name" \
        -v identifier_prefix="$IDENTIFIER_PREFIX" -v name_prefix="$NAME_PREFIX" \
        -v organisation="$ORGANISATION" "$COMMON_AWK"'
        FILENAME == ARGV[1] {
            if ($1 == "s" && $2 == "/name") { id = $3; id_line = $4 }
            if ($1 == "s" && $2 == "/displayName") { display = $3; display_line = $4 }
            if ($1 == "c" && $2 == "/author" && $3 == "{") author_line = $4
            if ($1 == "s" && $2 == "/author/url") { url = $3; url_line = $4 }
            next
        }
        { assemblies[++count] = $0 }
        END {
            manifest = package "/package.json"
            if (identifier_prefix != "") {
                expected = identifier_prefix tolower(name)
                if (id != expected) fail(at(manifest, id_line == "" ? 1 : id_line),
                    id == "" ? "package.json names no id." : "The id \047" id "\047 should be \047" expected "\047.")
            }
            if (name_prefix != "") {
                expected = name_prefix name
                if (display != expected) fail(at(manifest, display_line == "" ? 1 : display_line),
                    display == "" ? "package.json names no display name." : \
                    "The display name \047" display "\047 should be \047" expected "\047.")
            }
            if (organisation != "") {
                address = "https://github.com/" organisation "/"
                if (url == "" || index(url, address) != 1) {
                    line = url_line != "" ? url_line : author_line != "" ? author_line : 1
                    fail(at(manifest, line), url == "" ? "package.json names no author address." : \
                        "The author address \047" url "\047 is not under " address ".")
                }
            }
            if (name_prefix != "") {
                root = name_prefix name
                for (k = 1; k <= count; k++) {
                    split(assemblies[k], column, "\t")
                    space = column[5]
                    if (space != "" && space != root && index(space, root ".") != 1) {
                        fail(at(package "/" column[1], column[6] + 0),
                            "The root namespace \047" space "\047 of " column[3] " is not " root " or under it.")
                    }
                }
            }
        }' "$work/manifest.fields" "$work/assemblies"
}

rule_I4() {
    local maintainer=" $MAINTAINER_FILES "
    (
        cd "$package_folder" || exit 1
        awk -v rule=I4 -v package="$package_path" -v maintainer="$maintainer" "$COMMON_AWK"'
            function name_of(path) { sub(/^.*\//, "", path); return path }
            function entry(path,    name) {
                name = name_of(path)
                if (index(maintainer, " " name " ")) fail(package "/" path,
                    "The package holds the maintainer file " name ".")
                if (name == ".git") fail(package "/" path, "The package holds a .git entry.")
            }
            FILENAME == ARGV[1] {
                if (tolower(name_of($0)) == "resources") fail(package "/" $0, "The package holds a Resources folder.")
                else if (tolower($0) == "samples") fail(package "/" $0,
                    "The package holds a Samples folder without the tilde.")
                entry($0)
                next
            }
            {
                file = $0
                entry(file)
                if ((getline first < file) > 0) {
                    if (index(first, "version https://git-lfs.github.com/spec/v1") == 1) fail(package "/" file,
                        "The file " file " is a Git LFS pointer, not the file itself.")
                    if (tolower(file) ~ /\.asset$/) {
                        read = length(first) + 1; header = first
                        while (index(header, "m_EditorClassIdentifier") == 0 && read < 2048 &&
                            (getline header < file) > 0) read += length(header) + 1
                        if (index(header, "m_EditorClassIdentifier") &&
                            index(substr(header, index(header, "m_EditorClassIdentifier")), "PackageLedger"))
                            fail(package "/" file, "The asset " file " is a package ledger.")
                    }
                }
                close(file)
                if (name_of(file) == ".gitattributes") {
                    number = 0
                    while ((getline text < file) > 0) {
                        number++
                        text = trim(plain(text))
                        if (text != "" && substr(text, 1, 1) != "#" && index(text, "filter=lfs"))
                            fail(package "/" file ":" number, "The package\047s " file " names the LFS filter.")
                    }
                    close(file)
                }
            }' "$work/folders" "$work/files"
    ) || return
    if [ -n "$SCAFFOLD_FOLDER" ] && [ -f .gitattributes ]; then
        awk -v rule=I4 -v scaffold="${SCAFFOLD_FOLDER%/}/" "$COMMON_AWK"'
            {
                text = trim(plain($0))
                if (text == "" || substr(text, 1, 1) == "#" || !index(text, "filter=lfs")) next
                pattern = text; sub(/[ \t].*$/, "", pattern); sub(/^\//, "", pattern)
                if (index(pattern, scaffold) != 1)
                    fail(".gitattributes:" FNR, "The project\047s .gitattributes sends \047" pattern "\047 to LFS.")
            }' .gitattributes
    fi
}

rule_I5() {
    [ -n "$NAME_PREFIX" ] || return 0
    (
        cd "$package_folder" || exit 1
        awk -F '\t' -v rule=I5 -v package="$package_path" -v root="$NAME_PREFIX$package_name" "$COMMON_AWK$MASK_AWK"'
            function under(name) { return name == root || index(name, root ".") == 1 }
            BEGIN {
                namespace_declaration = "[^A-Za-z0-9_.]namespace[ \t]+[A-Za-z_][A-Za-z0-9_]*"
                namespace_declaration = namespace_declaration "([ \t]*[.][ \t]*[A-Za-z_][A-Za-z0-9_]*)*"
            }
            FILENAME == ARGV[1] {
                if (!under($3)) fail(at(package "/" $1, $4 + 0),
                    "The assembly \047" $3 "\047 is not named " root " or under it.")
                next
            }
            {
                file = $1; line = 0; in_comment = 0; in_verbatim = 0
                while ((getline raw < file) > 0) {
                    line++
                    code = " " mask(plain(raw))
                    while (match(code, namespace_declaration)) {
                        declared = substr(code, RSTART + 1, RLENGTH - 1)
                        sub(/^namespace[ \t]+/, "", declared); gsub(/[ \t]/, "", declared)
                        if (!under(declared)) fail(package "/" file ":" line,
                            "The namespace \047" declared "\047 is not " root " or under it.")
                        code = substr(code, RSTART + RLENGTH)
                    }
                }
                close(file)
            }' "$work/assemblies" "$work/sources"
    )
}

rule_I8() {
    awk -v rule=I8 -v package="$package_path" "$COMMON_AWK"'
        function hidden(path,    count, segment, k) {
            count = split(path, segment, "/")
            for (k = 1; k <= count; k++) if (substr(segment[k], 1, 1) == "." || segment[k] ~ /~$/) return 1
            return 0
        }
        FILENAME == ARGV[1] { folder[$0] = 1; folders[++folder_count] = $0; next }
        { file[$0] = 1; files[++file_count] = $0 }
        END {
            for (k = 1; k <= folder_count; k++) {
                if (!hidden(folders[k]) && !(folders[k] ".meta" in file))
                    fail(package "/" folders[k], "The folder " folders[k] " has no .meta file.")
            }
            for (k = 1; k <= file_count; k++) {
                path = files[k]
                if (path ~ /\.meta$/) {
                    owner = substr(path, 1, length(path) - 5)
                    if (!(owner in file) && !(owner in folder))
                        fail(package "/" path, "The .meta file " path " has no file or folder.")
                } else if (!hidden(path) && !(path ".meta" in file)) {
                    fail(package "/" path, "The file " path " has no .meta file.")
                }
            }
        }' "$work/folders" "$work/files"
}

rule_D5() {
    awk -F '\t' -v rule=D5 -v package="$package_path" "$COMMON_AWK"'
        FILENAME == ARGV[1] { name[$1] = $3; next }
        index($2, "GUID:") == 1 {
            fail(at(package "/" $1, $3 + 0), "\047" name[$1] "\047 references \047" $2 "\047 by GUID.")
        }
    ' "$work/assemblies" "$work/references"
}

rule_D6() {
    awk -F '\t' -v rule=D6 -v package="$package_path" -v floor="$FLOOR" "$COMMON_AWK"'
        $1 == "s" && $2 == "/unity" { unity = trim($3); unity_line = $4 }
        $1 == "s" && $2 ~ /^\/dependencies\// {
            dependency = substr($2, 15)
            if ($3 !~ /^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$/)
                fail(at(package "/package.json", $4 + 0),
                    "The dependency \047" dependency "\047 asks for \047" $3 "\047, which is not a plain version.")
        }
        END {
            if (floor != "" && unity != floor) fail(at(package "/package.json", unity_line == "" ? 1 : unity_line),
                "package.json holds " (unity == "" ? "no unity field" : "unity \047" unity "\047") \
                " where the floor editor is \047" floor "\047.")
        }' "$work/manifest.fields"
}

rule_C13() {
    local exempt=""
    [ -n "$FOUNDATION_PACKAGE" ] && [ "$package_id" = "$FOUNDATION_PACKAGE" ] && exempt=" $FOUNDATION_APPDOMAIN_TYPES "
    (
        cd "$package_folder" || exit 1
        awk -F '\t' -v rule=C13 -v package="$package_path" -v exempt="$exempt" "$COMMON_AWK$MASK_AWK"'
            function declares_only(full,    type, space, dot) {
                dot = full; sub(/\.[^.]*$/, "", dot); type = full; sub(/^.*\./, "", type)
                space = dot == full ? "" : dot
                if (declarations != 1 || !named[type]) return 0
                return space == "" ? namespace_count == 0 : (space in spaces)
            }
            {
                file = $1; assembly = $4; line = 0; in_comment = 0; in_verbatim = 0
                held = 0; declarations = 0; namespace_count = 0
                delete named; delete spaces
                while ((getline raw < file) > 0) {
                    line++
                    code = mask(plain(raw))
                    declarations += words_of(code, "class ") + words_of(code, "struct ")
                    declarations += words_of(code, "interface ") + words_of(code, "enum ")
                    rest = " " code
                    while (match(rest, /[^A-Za-z0-9_](class|struct)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
                        type = substr(rest, RSTART + 1, RLENGTH - 1); sub(/^(class|struct)[ \t]+/, "", type)
                        named[type] = 1
                        rest = substr(rest, RSTART + RLENGTH)
                    }
                    rest = " " code
                    while (match(rest, /[^A-Za-z0-9_.]namespace[ \t]+[A-Za-z_][A-Za-z0-9_.]*/)) {
                        space = substr(rest, RSTART + 1, RLENGTH - 1); sub(/^namespace[ \t]+/, "", space)
                        spaces[space] = 1; namespace_count++
                        rest = substr(rest, RSTART + RLENGTH)
                    }
                    for (w = 1; w <= 2; w++) {
                        word = w == 1 ? "AppDomain" : "DomainUnload"
                        count = words_of(code, word)
                        for (k = 1; k <= count; k++)
                            held_line[++held] = package "/" file ":" line "\t\047" word "\047 in " assembly "."
                    }
                }
                close(file)
                skip = 0
                if (exempt != "") {
                    total = split(exempt, types, " ")
                    for (k = 1; k <= total; k++) if (types[k] != "" && declares_only(types[k])) skip = 1
                }
                if (!skip) for (k = 1; k <= held; k++) { split(held_line[k], part, "\t"); fail(part[1], part[2]) }
            }' "$work/sources"
    )
}

rule_P2() {
    [ -n "$FOUNDATION_PACKAGE" ] && [ "$package_id" = "$FOUNDATION_PACKAGE" ] && return 0
    (
        cd "$package_folder" || exit 1
        awk -F '\t' -v rule=P2 -v package="$package_path" "$COMMON_AWK$MASK_AWK"'
            BEGIN {
                split("public private protected internal static readonly volatile new const unsafe", list, " ")
                for (k in list) modifier[list[k]] = 1
                split("trace traces traced tracing log logs logged logging", list, " ")
                for (k in list) switch_word[list[k]] = 1
                split("verbose verbosity debug debugging", list, " ")
                boolean_field = "[^A-Za-z0-9_.]((global[ \t]*::[ \t]*)?(System[ \t]*[.][ \t]*)?)(bool|Boolean)"
                boolean_field = boolean_field "[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*(;|,|=[^>]|=$)"
                for (k in list) switch_word[list[k]] = 1
            }
            function upper(c) { return c ~ /[A-Z]/ }
            function lower(c) { return c ~ /[a-z]/ }
            function digit(c) { return c ~ /[0-9]/ }
            function word_start(name, i,    current, previous) {
                current = substr(name, i, 1); previous = substr(name, i - 1, 1)
                if (current == "_" || previous == "_") return current != previous
                if (upper(current)) return !upper(previous) || (i < length(name) && lower(substr(name, i + 1, 1)))
                return digit(current) != digit(previous)
            }
            function is_switch(name,    start, i, word) {
                start = 1
                for (i = 2; i <= length(name) + 1; i++) {
                    if (i == length(name) + 1 || word_start(name, i)) {
                        word = substr(name, start, i - start); gsub(/^_+|_+$/, "", word)
                        if (tolower(word) in switch_word) return 1
                        start = i
                    }
                }
                return 0
            }
            function exposure(before,    is_public, is_static, is_serialized, depth, k, attribute, word) {
                while (1) {
                    sub(/[ \t]+$/, "", before)
                    if (before ~ /\]$/) {
                        depth = 0
                        for (k = length(before); k > 0; k--) {
                            if (substr(before, k, 1) == "]") depth++
                            else if (substr(before, k, 1) == "[") { depth--; if (depth == 0) break }
                        }
                        if (k == 0) break
                        attribute = " " substr(before, k) " "
                        if (attribute ~ /[^A-Za-z0-9_]SerializeField(Attribute)?[^A-Za-z0-9_]/) is_serialized = 1
                        before = substr(before, 1, k - 1)
                        continue
                    }
                    if (!match(before, /[A-Za-z0-9_]+$/)) break
                    word = substr(before, RSTART)
                    if (!(word in modifier)) break
                    if (word == "public") is_public = 1
                    if (word == "static" || word == "const") is_static = 1
                    before = substr(before, 1, RSTART - 1)
                }
                return is_static ? "static" : is_serialized ? "serialized" : is_public ? "public" : ""
            }
            function names_after(rest,    depth, k, c, found) {
                found = 0; depth = 0
                for (k = 1; k <= length(rest); k++) {
                    c = substr(rest, k, 1)
                    if (c ~ /[(\[{]/) depth++
                    else if (c ~ /[)\]}]/) { if (depth == 0) return found; depth-- }
                    else if (depth == 0 && c == ";") return found
                    else if (depth == 0 && c == ",") {
                        if (match(substr(rest, k + 1), /^[ \t]*[A-Za-z0-9_]+/)) {
                            extra[++found] = substr(rest, k + 1, RLENGTH); gsub(/[ \t]/, "", extra[found])
                        }
                    }
                }
                return found
            }
            $7 == 1 || $8 == 1 || ($10 != 1 && $9 == 1) { next }
            {
                file = $1; assembly = $4; line = 0; in_comment = 0; in_verbatim = 0; carried = ""
                while ((getline raw < file) > 0) {
                    line++
                    code = mask(plain(raw))
                    rest = code; offset = 0
                    while (match(" " rest, boolean_field)) {
                        start = RSTART; length_matched = RLENGTH
                        matched = substr(" " rest, start + 1, length_matched - 1)
                        before = carried " " substr(rest, 1, start - 1)
                        name = matched; sub(/^.*(bool|Boolean)[ \t]+/, "", name); sub(/[^A-Za-z0-9_].*$/, "", name)
                        kind = exposure(before)
                        if (kind != "") {
                            if (is_switch(name)) fail(package "/" file ":" line,
                                "\047" name "\047 is a " kind " diagnostic switch in " assembly ".")
                            after = substr(rest, start + index(matched, name) + length(name) - 1)
                            more = names_after(after)
                            for (k = 1; k <= more; k++) if (is_switch(extra[k])) fail(package "/" file ":" line,
                                "\047" extra[k] "\047 is a " kind " diagnostic switch in " assembly ".")
                        }
                        rest = substr(rest, start + length_matched - 1)
                    }
                    if (code ~ /[^ \t]/) carried = code
                }
                close(file)
            }' "$work/sources"
    )
}

changelog_headings() {
    awk "$COMMON_AWK"'
        function iso(date,    part, days) {
            if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
            split(date, part, "-")
            if (part[2] + 0 < 1 || part[2] + 0 > 12 || part[3] + 0 < 1) return 0
            days = substr("312931303130313130313031", (part[2] - 1) * 2 + 1, 2) + 0
            if (part[2] + 0 == 2 && !((part[1] % 4 == 0 && part[1] % 100 != 0) || part[1] % 400 == 0)) days = 28
            return part[3] + 0 <= days
        }
        {
            text = plain($0)
            if (substr(trim(text), 1, 3) == "```") { fenced = !fenced; next }
            if (fenced || !match(text, /^#+[ \t]+/)) next
            marks = text; sub(/[ \t].*$/, "", marks)
            if (length(marks) > 3) next
            title = trim(substr(text, RLENGTH + 1))
            version = ""; date = ""
            form = "[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?"
            rest = ""
            if (match(title, "^\\[" form "\\](\\([^() \t]*\\))?")) {
                version = substr(title, 2); sub(/\].*$/, "", version); rest = substr(title, RLENGTH + 1)
            }
            else if (match(title, "^" form)) { version = substr(title, 1, RLENGTH); rest = substr(title, RLENGTH + 1) }
            if (version != "") {
                if (rest == "") date = ""
                else if (match(rest, /^[ \t]+-[ \t]+./)) { date = trim(substr(rest, RLENGTH)) }
                else if (match(rest, /^[ \t]+\([^()]*\)$/)) {
                    date = rest; sub(/^[ \t]+\(/, "", date); sub(/\)$/, "", date); date = trim(date)
                }
                else version = ""
            }
            unreleased = title == "Unreleased" || title == "[Unreleased]"
            sub(/[ \t]+$/, "", text)
            printf "%d\t%d\t%d\t%s\t%s\t%d\t%s\n", FNR, length(marks), unreleased, version, date,
                date == "" || iso(date), text
        }' "$1"
}

rule_V1() {
    local changelog="$package_folder/CHANGELOG.md"
    if [ ! -f "$changelog" ]; then
        echo "failed: V1 $package_path/CHANGELOG.md The package has no CHANGELOG.md."
        return 0
    fi
    changelog_headings "$changelog" | awk -F '\t' -v rule=V1 -v package="$package_path" \
        -v version="$(field "$work/manifest.fields" /version | tr -d ' \t')" "$COMMON_AWK"'
        !top_found && ($3 == 1 || $4 != "" || $2 == 2) {
            top_found = 1
            if ($3 != 1 && $4 == "") fail(package "/CHANGELOG.md:" $1,
                "The top heading \047" $7 "\047 is neither Unreleased nor a version.")
            if ($4 != "" && version != "" && $4 != version) fail(package "/CHANGELOG.md:" $1,
                "The top entry is " $4 " and package.json holds " version ".")
        }
        $4 != "" && $5 != "" && $6 != 1 {
            fail(package "/CHANGELOG.md:" $1, "The date \047" $5 "\047 of " $4 " is not YYYY-MM-DD.")
        }
        END { if (!top_found) fail(package "/CHANGELOG.md", "CHANGELOG.md has no Unreleased or version heading.") }'
}

rule_V2() {
    local index_file="$package_folder/Documentation~/index.md"
    if [ ! -f "$index_file" ]; then
        echo "failed: V2 $package_path/Documentation~/index.md Documentation~/index.md is missing."
        return 0
    fi
    awk -v rule=V2 -v package="$package_path" "$COMMON_AWK"'
        { text = trim(plain($0)); if (text != "" && substr(text, 1, 1) != "#") written = 1 }
        END {
            if (!written)
                fail(package "/Documentation~/index.md", "Documentation~/index.md holds nothing beyond headings.")
        }' "$index_file"
}

rule_V6() {
    local version line newest
    version="$(field "$work/manifest.fields" /version | tr -d ' \t')"
    line="$(field_line "$work/manifest.fields" /version)"
    if [ -z "$version" ]; then
        echo "failed: V6 $package_path/package.json package.json names no version."
        return 0
    fi
    newest=""
    [ -f "$package_folder/CHANGELOG.md" ] && newest="$(changelog_headings "$package_folder/CHANGELOG.md" \
        | awk -F '\t' '$4 != "" && $5 != "" { print $4; exit }')"
    if [ -z "$newest" ]; then
        [ "$version" = "0.0.0" ] || echo "failed: V6 $package_path/package.json:$line The version is $version and" \
            "CHANGELOG.md has no released entry."
    elif [ "$version" != "$newest" ]; then
        echo "failed: V6 $package_path/package.json:$line The version is $version and the newest released entry" \
            "in CHANGELOG.md is $newest."
    fi
}

rule_A3() {
    local agents="$package_folder/AGENTS.md"
    if [ ! -f "$agents" ]; then
        echo "failed: A3 $package_path/AGENTS.md The package ships no AGENTS.md."
        return 0
    fi
    awk -v rule=A3 -v package="$package_path" -v address="$LINE_TEXT_ADDRESS" "$COMMON_AWK"'
        BEGIN { count = split("Purpose|Front door|Rules|Not for|Gaps|Ledger", heading, "|") }
        {
            text = plain($0)
            for (k = 1; k <= count; k++) if (!(k in found) && index(text, "## " heading[k])) found[k] = FNR
            if (collecting && substr(text, 1, 3) == "## ") collecting = 0
            if (collecting && index(text, address)) pointed = 1
            line_end = text; sub(/[ \t]+$/, "", line_end)
            if (!seen_rules && line_end == "## Rules") { collecting = 1; seen_rules = 1 }
        }
        END {
            previous = -1
            for (k = 1; k <= count; k++) {
                if (!(k in found)) {
                    fail(package "/AGENTS.md", "AGENTS.md has no \047" heading[k] "\047 heading.")
                    continue
                }
                if (found[k] < previous)
                    fail(package "/AGENTS.md:" found[k], "The \047" heading[k] "\047 heading is out of order.")
                previous = found[k]
            }
            if (seen_rules && address != "" && !pointed)
                fail(package "/AGENTS.md:" found[3], "The Rules section does not point at the line text.")
        }' "$agents"
}

rule_S1() {
    awk -F '\t' -v rule=S1 -v package="$package_path" "$COMMON_AWK"'
        FILENAME == ARGV[1] {
            if ($1 == "c" && $2 == "/samples" && $3 == "[") listed = 1
            if ($1 == "c" && $2 ~ /^\/samples\/[0-9]+$/) {
                k = substr($2, 10) + 1; if (k > samples) samples = k; sample_line[k] = $4
            }
            if ($1 == "s" && $2 ~ /^\/samples\/[0-9]+\/path$/) {
                k = substr($2, 10); sub(/\/.*$/, "", k); sample_path[k + 1] = $3
            }
            if ($1 == "s" && $2 ~ /^\/samples\/[0-9]+\/displayName$/) {
                k = substr($2, 10); sub(/\/.*$/, "", k); sample_name[k + 1] = $3
            }
            next
        }
        FILENAME == ARGV[2] {
            folder[$0] = 1
            if (index($0, "Samples~/") == 1 && index(substr($0, 10), "/") == 0) sample_folders[++folder_count] = $0
            next
        }
        END {
            manifest = package "/package.json"
            if (!listed) {
                if (folder_count > 0)
                    fail(manifest, "Samples~ holds sample folders and package.json has no samples entry.")
                exit
            }
            for (k = 1; k <= samples; k++) {
                path = trim(sample_path[k]); gsub(/\\/, "/", path); sub(/\/+$/, "", path)
                if (substr(path, 1, 2) == "./") path = substr(path, 3)
                named[path] = 1
                if (path == "" || !(path in folder)) fail(at(manifest, sample_line[k] + 0),
                    "The sample \047" sample_name[k] "\047 names the path \047" sample_path[k] \
                    "\047, which is not a folder of the package.")
            }
            for (k = 1; k <= folder_count; k++) if (!(sample_folders[k] in named))
                fail(package "/" sample_folders[k], "The sample folder " sample_folders[k] " has no samples entry.")
        }' "$work/manifest.fields" "$work/folders"
}

list_project_content() {
    local version_file project folder
    project_content=()
    while IFS= read -r version_file; do
        project="${version_file%/ProjectSettings/ProjectVersion.txt}"
        for folder in $NEVER_CONTENT_FOLDERS; do
            [ "${#project_content[@]}" -eq 0 ] || project_content+=(-o)
            project_content+=(-path "$project/$folder")
        done
    done < <(find . \( -name .git -o -name '*~' -o -type d \( "${never_content[@]}" \) \) -prune \
        -o -path '*/ProjectSettings/ProjectVersion.txt' -type f -print)
    [ "${#project_content[@]}" -gt 0 ] || project_content=(-path "")
}

check_organisation() {
    [ -n "$OLD_ORGANISATION" ] || return 0
    list_project_content
    find . -type d \( "${project_content[@]}" \) -prune -o \( -path ./.git -o -name '*~' \) -prune \
        -o -type f -print \
        | sed 's|^\./||' | grep -v '^scripts/check\.sh$' | sort \
        | awk -v rule=organisation -v old="$OLD_ORGANISATION" -v organisation="$ORGANISATION" "$COMMON_AWK"'
            {
                file = $0; line = 0
                while ((getline text < file) > 0) {
                    line++
                    if (index(text, old)) fail(file ":" line,
                        "names the placeholder organisation " old "; the organisation is " organisation ".")
                }
                close(file)
            }'
}

check_studio_package() {
    [ -n "$STUDIO_PACKAGE_PATTERN" ] || return 0
    local folder
    for folder in $STUDIO_PACKAGE_PATTERN; do
        [ -d "$folder" ] || continue
        echo "failed: studio-package $folder is a Studio package inside this repository's Packages folder;" \
            "a game installs it from its own repository."
    done
}

check_version() {
    [ -n "$manifests" ] || return 0
    local base="" source=""
    if [ -n "$VERSION_BASE_FOLDER" ]; then
        source="folder"
    elif [ -n "${GITHUB_BASE_REF:-}" ]; then
        if git rev-parse --verify --quiet "origin/$GITHUB_BASE_REF" > /dev/null 2>&1; then
            base="origin/$GITHUB_BASE_REF"
        else
            echo "skipped: version check needs a base branch, and origin/$GITHUB_BASE_REF is not fetched"
            return 0
        fi
    else
        base="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
        if [ -z "$base" ]; then
            echo "skipped: version check needs a base branch"
            return 0
        fi
    fi
    local manifest current previous line
    while IFS= read -r manifest; do
        if [ "$source" = "folder" ]; then
            [ -f "$VERSION_BASE_FOLDER/$manifest" ] || continue
            cp "$VERSION_BASE_FOLDER/$manifest" "$work/base.json"
        else
            git show "$base:./$manifest" > "$work/base.json" 2>/dev/null || continue
        fi
        read_fields "$manifest" > "$work/head.fields"
        read_fields "$work/base.json" > "$work/base.fields"
        current="$(field "$work/head.fields" /version)"
        previous="$(field "$work/base.fields" /version)"
        line="$(field_line "$work/head.fields" /version)"
        if [ "$current" != "$previous" ]; then
            echo "failed: version $manifest:$line The version changed from $previous to $current" \
                "against ${base:-$VERSION_BASE_FOLDER}; the release writes the version."
        fi
    done <<< "$manifests"
}

check_line_text_pointer() {
    run_script check-line-text-pointer.sh line-text-pointer "$root"
}

check_line_endings() {
    run_script check-line-endings.sh line-endings
}

run_script() {
    local script="$script_folder/$1" name="$2"
    shift 2
    if [ ! -f "$script" ]; then
        echo "failed: $name scripts/$1 is missing beside check.sh."
        return 0
    fi
    local output status
    output="$(bash "$script" "$@" 2>&1)"
    status=$?
    printf '%s\n' "$output" | sed -n "s|^failed: |failed: $name |p"
    if [ "$status" -ne 0 ] && ! printf '%s\n' "$output" | grep -q '^failed: '; then
        echo "failed: $name scripts/${script##*/} exited $status: $(printf '%s' "$output" | tail -n 1)"
    fi
}

wanted() {
    [ -z "$only" ] || [ "$only" = "$1" ]
}

manifests=""
for manifest in Packages/*/package.json; do
    [ -f "$manifest" ] || continue
    [ "$manifest" = "Packages/PackageName/package.json" ] && continue
    manifests="$manifests$manifest"$'\n'
done
manifests="${manifests%$'\n'}"

if [ -z "$manifests" ]; then
    echo "skipped: no Packages/<Name>/package.json here, so the template checks run alone"
else
    while IFS= read -r manifest; do
        package_path="${manifest%/package.json}"
        package_name="${package_path#Packages/}"
        package_folder="$root/$package_path"
        list_package
        read_fields "$manifest" > "$work/manifest.fields"
        package_id="$(field "$work/manifest.fields" /name)"
        read_assemblies
        for rule in "${RULES[@]}"; do
            wanted "$rule" || continue
            output="$("rule_$rule")"
            report "$output" "$rule" "$?"
        done
    done <<< "$manifests"
    for rule in "${RULES[@]}"; do
        wanted "$rule" && rules_run=$((rules_run + 1))
    done
fi

for check in "${TEMPLATE_CHECKS[@]}"; do
    wanted "$check" || continue
    checks_run=$((checks_run + 1))
    output="$("check_${check//-/_}")"
    report "$output" "$check" "$?"
done

if [ "$finding_count" -gt 0 ]; then
    echo "failed: $finding_count findings"
    exit 1
fi
echo "succeeded: $rules_run rules, $checks_run template checks"
exit 0

#!/usr/bin/env bash
set -euo pipefail

STRANGERS_TIMEOUT_SECONDS=7200
EDITOR_START_TIMEOUT_SECONDS=1200
POLL_SECONDS=20
DRY_RUN="${DRY_RUN:-0}"
WORK_FOLDER="${RUN_STRANGERS_WORK:-}"

usage() {
    cat >&2 <<'TEXT'
usage: bash scripts/run-strangers.sh <tag> | --commit <sha> [--root <folder>]

Runs the stranger projects that install this repository's package against a candidate pushed to origin: a
tag, or with --commit a commit at the head of a branch or tag. Every stranger's packages-lock.json must hold
the candidate for the package. Finds the editor of the strangers' test bed by its process, or opens it
headless and closes that one at the end, lists the strangers with packagecheck strangers, runs the line tier
over each one in turn, polling each run until it finished or failed, then prints the table and the
post-status.sh line to type for the strangers status. --root is the strangers folder, by default Strangers
in the StrangersDev checkout beside this one. DRY_RUN set to anything but 0 prints the plan and runs
nothing. RUN_STRANGERS_WORK names the folder for the report.
TEXT
}

say() {
    printf '%s\n' "$*"
}

stop() {
    printf '%s\n' "$*" >&2
    exit 1
}

value_of() {
    if [ "$1" -lt 2 ] || [ -z "$2" ] || [ "${2#--}" != "$2" ]; then
        usage
        exit 2
    fi
}

dry_run="false"
case "$DRY_RUN" in
    ""|0) ;;
    *) dry_run="true" ;;
esac

tag=""
commit=""
strangers_root=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --commit) value_of "$#" "${2:-}"; commit="$2"; shift 2 ;;
        --root) value_of "$#" "${2:-}"; strangers_root="$2"; shift 2 ;;
        -*) usage; exit 2 ;;
        *)
            [ -z "$tag" ] || { usage; exit 2; }
            tag="$1"; shift ;;
    esac
done

if { [ -z "$tag" ] && [ -z "$commit" ]; } || { [ -n "$tag" ] && [ -n "$commit" ]; }; then
    usage
    exit 2
fi

root="$(git rev-parse --show-toplevel)"
cd "$root"

if [ -n "$tag" ]; then
    candidate="$(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}" | tail -n 1 | cut -f 1)"
    [ -n "$candidate" ] || stop "No tag $tag on origin: push the tag first"
    candidate_ref="refs/tags/$tag"
else
    remote_line="$(git ls-remote origin | awk -v sha="$commit" 'index($1, sha) == 1 { print; exit }')"
    [ -n "$remote_line" ] || stop "$commit is not the head of a branch or tag on origin: push it first"
    candidate="$(printf '%s\n' "$remote_line" | cut -f 1)"
    candidate_ref="$(printf '%s\n' "$remote_line" | cut -f 2)"
fi

git cat-file -e "$candidate^{commit}" 2>/dev/null \
    || stop "$candidate ($candidate_ref) is not in this checkout: git fetch origin first"
branch="$(git rev-parse --abbrev-ref HEAD)"
git merge-base --is-ancestor "$candidate" HEAD \
    || stop "$candidate is not reachable from $branch: check out a branch that holds it, so post-status.sh takes it"

package_id=""
for package_file in Packages/*/package.json; do
    [ -f "$package_file" ] || continue
    package_id="$(tr -d '\r' < "$package_file" | sed -n 's/^ *"name": *"\([^"]*\)".*/\1/p' | head -n 1)"
done
[ -n "$package_id" ] || stop "This repository holds no package under Packages/"

[ -n "$strangers_root" ] || strangers_root="$(dirname "$root")/StrangersDev/Strangers"
[ -d "$strangers_root" ] || stop "No strangers folder at \"$strangers_root\": pass --root <folder>"
strangers_root="$(cd "$strangers_root" && pwd)"
project="$(dirname "$strangers_root")"
version_file="$project/ProjectSettings/ProjectVersion.txt"
[ -f "$version_file" ] || stop "\"$project\" is not a Unity project: it has no ProjectSettings/ProjectVersion.txt"
project_version="$(tr -d '\r' < "$version_file" | sed -n 's/^m_EditorVersion: *//p' | head -n 1)"

[ -n "$WORK_FOLDER" ] || WORK_FOLDER="${TMPDIR:-/tmp}/run-strangers/$(basename "$project")"

say "run-strangers: $package_id at $candidate ($candidate_ref on origin) over \"$strangers_root\""

on_windows() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

native_path() {
    if command -v cygpath > /dev/null 2>&1; then
        cygpath -m "$1"
    else
        printf '%s\n' "$1"
    fi
}

posix_path() {
    if command -v cygpath > /dev/null 2>&1; then
        cygpath -u "$1"
    else
        printf '%s\n' "$1"
    fi
}

decode() {
    awk '{ gsub(/\\n/, "\n"); gsub(/\\"/, "\""); gsub(/\\t/, "\t"); print }'
}

editor_processes() {
    if on_windows; then
        powershell.exe -NoProfile -Command \
            "Get-CimInstance Win32_Process -Filter \"name='Unity.exe'\" |
            ForEach-Object { [string]\$_.ProcessId + ' ' + \$_.CommandLine }" | tr -d '\r'
    else
        ps -eo pid=,args= | grep '[U]nity' || true
    fi
}

editor_pid_for() {
    local wanted
    wanted="$(native_path "$1" | tr 'A-Z\\' 'a-z/' | sed 's|/*$||')"
    editor_processes | tr -d '"' | tr 'A-Z\\' 'a-z/' | grep -v 'assetimportworker' \
        | awk -v wanted="$wanted" 'index($0 " ", "-projectpath " wanted " ") > 0 { print $1; exit }'
}

process_id_of() {
    if [ -r "/proc/$1/winpid" ]; then
        tr -d '\r\n' < "/proc/$1/winpid"
    else
        printf '%s\n' "$1"
    fi
}

editor_alive() {
    if on_windows; then
        editor_processes | awk -v pid="$1" '$1 == pid { found = 1 } END { exit !found }'
    else
        kill -0 "$1" 2>/dev/null
    fi
}

editor_executable() {
    local location
    location="$(unity editors --installed --long --format tsv --no-header 2>/dev/null \
        | awk -F '\t' -v version="$1" '$1 == version { print $4; exit }')"
    [ -z "$location" ] || posix_path "$location"
}

lock_hash() {
    local lock="$1/Packages/packages-lock.json"
    [ -f "$lock" ] || return 0
    tr -d '\r' < "$lock" | awk -v package="\"$package_id\": {" '
        index($0, package) > 0 { inside = 1; next }
        inside && /^    "[^"]+": \{/ { exit }
        inside && /"hash": *"/ { sub(/.*"hash": *"/, ""); sub(/".*/, ""); print; exit }'
}

lock_mismatches() {
    local folder name hash
    for folder in "$strangers_root"/*/; do
        name="$(basename "$folder")"
        grep -q "\"$package_id\"" "$folder/Packages/manifest.json" 2>/dev/null || continue
        hash="$(lock_hash "$folder")"
        if [ "$hash" != "$candidate" ]; then
            say "the stranger $name holds ${hash:-no locked commit}; update its lock to $candidate first"
        fi
    done
}

strangers_root_native="$(native_path "$strangers_root")"
editor_pid="$(editor_pid_for "$project")"
mismatches="$(lock_mismatches)"

if [ "$dry_run" = "true" ]; then
    if [ -n "$editor_pid" ]; then
        say "plan: use the editor of \"$project\", process $editor_pid"
    else
        say "plan: open \"$project\" headless in $project_version" \
            "(\"$(editor_executable "$project_version")\"), close that one at the end"
    fi
    if [ -n "$mismatches" ]; then
        printf '%s\n' "$mismatches" | sed 's/^/plan: refuse, /'
    else
        say "plan: every stranger that installs $package_id holds $candidate in its lock"
    fi
    say "plan: packagecheck strangers --root \"$strangers_root_native\"," \
        "keep the projects whose manifest installs $package_id"
    say "plan: for each of them in turn, packagecheck run-start --tier line --path \"$strangers_root_native/<name>\""
    say "plan: packagecheck run-status --run <id> every $POLL_SECONDS s until finished or failed," \
        "at most $STRANGERS_TIMEOUT_SECONDS s, before the next"
    say "plan: print the table, then: bash scripts/post-status.sh --sha $candidate --state <success|failure>" \
        "--context strangers --description \"<n> projects, <m> failed\" --report \"$WORK_FOLDER/strangers.txt\""
    exit 0
fi

if [ -n "$mismatches" ]; then
    printf '%s\n' "$mismatches" >&2
    stop "No status line: every stranger must run on the candidate."
fi

mkdir -p "$WORK_FOLDER"
WORK_FOLDER="$(cd "$WORK_FOLDER" && pwd)"

lock_file="$project/Temp/spellbound-gate.lock"
if [ -f "$lock_file" ]; then
    holder="$(tr -d '\r\n' < "$lock_file")"
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
        stop "Another gate run holds $lock_file (process $holder). Wait for it to end."
    fi
fi
mkdir -p "$project/Temp"
printf '%s\n' "$$" > "$lock_file"

launched_pid=""

finish_run() {
    if [ -n "$launched_pid" ] && editor_alive "$launched_pid" \
        && [ "$(editor_pid_for "$project")" = "$launched_pid" ]; then
        unity close "$(native_path "$project")" > /dev/null 2>&1 \
            || unity close "$(native_path "$project")" --force > /dev/null 2>&1 || true
    fi
    rm -f "$lock_file"
}
trap finish_run EXIT

if [ -z "$editor_pid" ]; then
    executable="$(editor_executable "$project_version")"
    [ -n "$executable" ] \
        || stop "The test bed's editor $project_version is not installed: unity install $project_version"
    editor_log="$WORK_FOLDER/editor.log"
    say "opening \"$project\" headless in $project_version, log \"$editor_log\""
    "$executable" -batchmode -nographics -projectPath "$(native_path "$project")" \
        -logFile "$(native_path "$editor_log")" > /dev/null 2>&1 &
    child="$!"
    deadline=$((SECONDS + EDITOR_START_TIMEOUT_SECONDS))
    until [ -n "$editor_pid" ] && unity command --pid "$editor_pid" editor_status > /dev/null 2>&1; do
        kill -0 "$child" 2>/dev/null || stop "The editor exited while opening the test bed: see \"$editor_log\""
        [ "$SECONDS" -lt "$deadline" ] \
            || stop "The editor did not answer in $EDITOR_START_TIMEOUT_SECONDS s: see \"$editor_log\""
        sleep "$POLL_SECONDS"
        child_pid="$(process_id_of "$child")"
        if [ -z "$launched_pid" ] && [ "$(editor_pid_for "$project")" = "$child_pid" ]; then
            launched_pid="$child_pid"
            editor_pid="$child_pid"
        fi
    done
fi

operation_word=""
operation_text=""

operation() {
    local output code=0
    output="$(unity command --pid "$editor_pid" spellbound_run --line "$1" --result-only 2>&1)" || code=$?
    if [ "$code" -eq 0 ]; then
        operation_text="$(printf '%s' "$output" | sed '1s/^"//; $s/"$//')"
    else
        operation_text="$(printf '%s\n' "$output" | sed -n 's/.*Command Execution Failed\. \(.*\)"[,]*$/\1/p' \
            | head -n 1)"
    fi
    operation_text="$(printf '%s\n' "$operation_text" | decode)"
    operation_word="$(printf '%s\n' "$operation_text" | sed -n '1s/^\([a-z-]*\):.*/\1/p')"
    if [ -z "$operation_word" ]; then
        operation_word="failed"
        operation_text="failed: the editor did not answer $1: $(printf '%s\n' "$output" \
            | sed -n 's/.*"message": *"\(.*\)",*$/\1/p' | head -n 1)"
    fi
}

operation "packagecheck strangers --root \"$strangers_root_native\""
printf '%s\n' "$operation_text" > "$WORK_FOLDER/strangers-list.txt"
[ "$operation_word" = "succeeded" ] || stop "$operation_text"

projects="$(printf '%s\n' "$operation_text" | awk -v package="$package_id" '
    /^[^ ]+ on Unity / { current = $1; next }
    current != "" && index($0, "  " package ":") == 1 { print current }')"
[ -n "$projects" ] || stop "No stranger under \"$strangers_root\" installs $package_id"
say "strangers that install $package_id:$(printf ' %s' $projects)"

details="$WORK_FOLDER/strangers-details.txt"
rows="$WORK_FOLDER/strangers-rows.txt"
: > "$details"
: > "$rows"

run_stranger() {
    local name="$1" run_id stage="" result line deadline
    operation "packagecheck run-start --tier line --path \"$strangers_root_native/$name\""
    if [ "$operation_word" != "succeeded" ]; then
        printf '%s\t%s\t%s\n' "$name" "$operation_word" "$(printf '%s\n' "$operation_text" | head -n 1)" >> "$rows"
        return
    fi
    run_id="$(printf '%s\n' "$operation_text" | sed -n '1s/.*run \([^ ]*\) started.*/\1/p')"
    say "$name: run $run_id started"
    deadline=$((SECONDS + STRANGERS_TIMEOUT_SECONDS))
    while [ "$SECONDS" -lt "$deadline" ]; do
        sleep "$POLL_SECONDS"
        if ! editor_alive "$editor_pid"; then
            operation_word="failed"
            operation_text="failed: the editor, process $editor_pid, exited during the run"
            break
        fi
        operation "packagecheck run-status --run $run_id"
        stage="$(printf '%s\n' "$operation_text" | head -n 1 | sed 's/.*: //')"
        [ "$operation_word" = "succeeded" ] || break
        case "$stage" in
            finished|failed) break ;;
        esac
    done
    printf '== %s, run %s\n%s\n\n' "$name" "$run_id" "$operation_text" >> "$details"
    line="$(printf '%s\n' "$operation_text" | grep '^L1 ' | head -n 1 || true)"
    if [ "$operation_word" != "succeeded" ]; then
        result="$operation_word"
        line="$(printf '%s\n' "$operation_text" | head -n 1)"
    elif [ "$stage" != "finished" ] && [ "$stage" != "failed" ]; then
        result="timed out"
        line="no end in $STRANGERS_TIMEOUT_SECONDS s, last stage $stage"
    elif [ "$stage" = "finished" ] && [ "${line#L1 passed}" != "$line" ]; then
        result="passed"
    else
        result="failed"
    fi
    printf '%s\t%s\t%s\n' "$name" "$result" "${line:-no L1 result}" >> "$rows"
    say "$name: $result"
}

project_count=0
for name in $projects; do
    project_count=$((project_count + 1))
    run_stranger "$name"
done

report="$WORK_FOLDER/strangers.txt"
{
    printf '%-20s %-10s %s\n' project result line
    awk -F '\t' '{ printf "%-20s %-10s %s\n", $1, $2, $3 }' "$rows"
    printf '\n'
    cat "$details"
} > "$report"
say ""
awk -F '\t' 'BEGIN { printf "%-20s %-10s %s\n", "project", "result", "line" }
    { printf "%-20s %-10s %s\n", $1, $2, $3 }' "$rows"

failed_count="$(awk -F '\t' '$2 != "passed"' "$rows" | wc -l | tr -d ' ')"
state="success"
[ "$failed_count" -eq 0 ] || state="failure"
say ""
say "bash scripts/post-status.sh --sha $candidate --state $state --context strangers" \
    "--description \"$project_count projects, $failed_count failed\" --report \"$report\""
[ "$state" = "success" ]

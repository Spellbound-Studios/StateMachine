#!/usr/bin/env bash
set -euo pipefail

JOBS=(tests-edit tests-play packagecheck-check packagecheck-surface core-ledger core-validate artpipeline-check
    floor-compile floor-tests soak)
CANARIES=(canary-beta canary-coreclr)
SETTINGS_FILE="$(dirname "${BASH_SOURCE[0]}")/check.sh"
FLOOR="${FLOOR-$(sed -n 's/^FLOOR="\${FLOOR-\([^}]*\)}"$/\1/p' "$SETTINGS_FILE" 2>/dev/null | head -n 1)}"
CANARY_EDITOR="${CANARY_EDITOR-6000.7}"
CANARY_DESCRIPTION_LIMIT=120
BASE_BRANCHES=(origin/beta origin/main)
EDITOR_START_TIMEOUT_SECONDS=1200
TEST_TIMEOUT_SECONDS=3600
FLOOR_TIMEOUT_SECONDS=3600
COMPILE_TIMEOUT_SECONDS=600
POLL_SECONDS=15
WORK_FOLDER="${RUN_LOCAL_TESTS_WORK:-}"

usage() {
    cat >&2 <<'TEXT'
usage: bash scripts/run-local-tests.sh [--project <folder>] [--base <branch>] [--only <job>] [--editor <version>]
                                       [--keep-copy] [--canaries]

The local gate an author runs before asking for review. Runs the jobs listed at the top of this script in
order over the dev project, each printing its status word, its name, a summary and its seconds, then prints
the table and, after a run of every job on a clean working tree, the post-status.sh line to type for the
unity-tests status. A job that does not apply says why. The project's editor is found by its process; when
none runs, the script opens one headless and closes that one at the end. The floor jobs open a throwaway
copy without Library in the newest installed editor of the floor (FLOOR at the top, a major and minor such
as 6000.3, read from the environment first), named in the first line and removed at the end unless
--keep-copy is given; they are not applicable when the project's editor is at the floor, and fail with the
install line when no editor of the floor is installed. --base defaults to the first of the base branches at
the top that exists; the paths changed against it decide the ledger, validation and art jobs. --only runs
one job. --editor names the floor editor's exact version instead. RUN_LOCAL_TESTS_WORK names the folder for
the logs, the table and the copies.

The canaries listed at the top are outside the gate and run only on demand: --canaries runs both and --only
runs one. Each reads the newest installed editor of CANARY_EDITOR (a major and minor such as 6000.7, read
from the environment first): canary-beta compiles a throwaway copy without Library in it, counting error CS,
naming the first and listing the UAC warnings by code; canary-coreclr reads its Windows player module for a
CoreCLR variation. A canary that ran on a clean working tree prints the post-status.sh line for its
unity-canary-<name> status; its result never changes the gate's status line or exit code.
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

project=""
base=""
only=""
floor_override=""
keep_copy="false"
canaries="false"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --project) value_of "$#" "${2:-}"; project="$2"; shift 2 ;;
        --base) value_of "$#" "${2:-}"; base="$2"; shift 2 ;;
        --only) value_of "$#" "${2:-}"; only="$2"; shift 2 ;;
        --editor) value_of "$#" "${2:-}"; floor_override="$2"; shift 2 ;;
        --keep-copy) keep_copy="true"; shift ;;
        --canaries) canaries="true"; shift ;;
        *) usage; exit 2 ;;
    esac
done

is_canary() {
    local name
    for name in "${CANARIES[@]}"; do
        [ "$name" != "$1" ] || return 0
    done
    return 1
}

is_job() {
    local name
    for name in "${JOBS[@]}"; do
        [ "$name" != "$1" ] || return 0
    done
    is_canary "$1"
}

selected=("${JOBS[@]}")
if [ -n "$only" ]; then
    [ "$canaries" = "false" ] || stop "--only and --canaries cannot be given together"
    is_job "$only" || stop "No job is called $only. The jobs: ${JOBS[*]}. The canaries: ${CANARIES[*]}"
    selected=("$only")
elif [ "$canaries" = "true" ]; then
    only="${CANARIES[*]}"
    selected=("${CANARIES[@]}")
fi

gate_selected="false"
for job in "${selected[@]}"; do
    is_canary "$job" || gate_selected="true"
done

[ -n "$project" ] || project="$(git rev-parse --show-toplevel)"
project="$(cd "$project" && pwd)"
version_file="$project/ProjectSettings/ProjectVersion.txt"
[ -f "$version_file" ] || stop "$project is not a Unity project: it has no ProjectSettings/ProjectVersion.txt"
project_version="$(tr -d '\r' < "$version_file" | sed -n 's/^m_EditorVersion: *//p' | head -n 1)"
project_name="$(basename "$project")"
head_commit="$(git -C "$project" rev-parse HEAD)"

working_changes="$(git -C "$project" status --porcelain --untracked-files=no)"
if [ -n "$working_changes" ] && [ -z "$only" ]; then
    stop "The working tree has changes to tracked files. The gate attests a commit: commit or stash them first."
fi

package_name=""
for package_file in "$project"/Packages/*/package.json; do
    [ -f "$package_file" ] || continue
    package_name="$(basename "$(dirname "$package_file")")"
done

if [ -z "$base" ]; then
    for candidate_base in "${BASE_BRANCHES[@]}"; do
        if git -C "$project" rev-parse --verify --quiet "$candidate_base" > /dev/null; then
            base="$candidate_base"
            break
        fi
    done
fi
changed=""
if [ -n "$base" ]; then
    changed="$(git -C "$project" diff --name-only "$base...HEAD")"
fi

[ -n "$WORK_FOLDER" ] || WORK_FOLDER="${TMPDIR:-/tmp}/run-local-tests/$project_name"
mkdir -p "$WORK_FOLDER"
WORK_FOLDER="$(cd "$WORK_FOLDER" && pwd)"

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

modified_seconds() {
    if stat -c %Y "$1" > /dev/null 2>&1; then
        stat -c %Y "$1"
    elif stat -f %m "$1" > /dev/null 2>&1; then
        stat -f %m "$1"
    else
        python3 -c 'import os, sys; print(int(os.path.getmtime(sys.argv[1])))' "$1"
    fi
}

with_timeout() {
    if command -v timeout > /dev/null 2>&1; then
        timeout "$@"
    else
        shift
        "$@"
    fi
}

decode() {
    awk '{ gsub(/\\n/, "\n"); gsub(/\\"/, "\""); gsub(/\\t/, "\t"); print }'
}

copy_root="$WORK_FOLDER/$project_name-floor"
canary_root="$WORK_FOLDER/$project_name-canary"

copy_folder() {
    printf '%s\n' "${2:-$copy_root}/$1"
}

lock_file="$project/Temp/spellbound-gate.lock"
if [ -f "$lock_file" ]; then
    holder="$(tr -d '\r\n' < "$lock_file")"
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
        stop "Another gate run holds $lock_file (process $holder). Wait for it to end."
    fi
fi
mkdir -p "$project/Temp"
printf '%s\n' "$$" > "$lock_file"

editor_pid=""
editor_log=""
launched_pid=""
copies_made="false"

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

editor_log_of() {
    local log
    log="$(editor_processes | awk -v pid="$1" '
        $1 == pid {
            at = index(tolower($0), "-logfile ")
            if (at == 0) { exit }
            rest = substr($0, at + 9)
            sub(/^ +/, "", rest)
            if (substr(rest, 1, 1) == "\"") {
                rest = substr(rest, 2)
                print substr(rest, 1, index(rest, "\"") - 1)
            } else {
                end = index(rest, " -")
                print (end > 0 ? substr(rest, 1, end - 1) : rest)
            }
            exit
        }')"
    if [ -n "$log" ] && [ "$log" != "-" ]; then
        posix_path "$log"
    elif [ -n "${LOCALAPPDATA:-}" ]; then
        posix_path "$LOCALAPPDATA/Unity/Editor/Editor.log"
    fi
}

editor_executable() {
    local location
    location="$(unity editors --installed --long --format tsv --no-header 2>/dev/null \
        | awk -F '\t' -v version="$1" '$1 == version { print $4; exit }')"
    [ -z "$location" ] || posix_path "$location"
}

close_launched_editor() {
    if [ -n "$launched_pid" ] && editor_alive "$launched_pid" \
        && [ "$(editor_pid_for "$project")" = "$launched_pid" ]; then
        unity close "$(native_path "$project")" > /dev/null 2>&1 \
            || unity close "$(native_path "$project")" --force > /dev/null 2>&1 || true
    fi
    if [ -n "$launched_pid" ] && [ "$editor_pid" = "$launched_pid" ]; then
        editor_pid=""
    fi
    launched_pid=""
}

finish_run() {
    close_launched_editor
    if [ "$copies_made" = "true" ] && [ "$keep_copy" = "false" ]; then
        rm -rf "$copy_root" "$canary_root"
    fi
    rm -f "$lock_file"
}
trap finish_run EXIT

newest_installed_editor() {
    unity editors --installed --long --format tsv --no-header 2>/dev/null | awk -F '\t' -v floor="$1" '
        index($1, floor ".") == 1 {
            rest = substr($1, length(floor) + 2)
            if (!match(rest, /^[0-9]+/)) { next }
            patch = substr(rest, 1, RLENGTH)
            kind = substr(rest, RLENGTH + 1, 1)
            build = substr(rest, RLENGTH + 2) + 0
            rank = index("abfp", kind)
            print patch, rank, build, $1
        }' | sort -n -k1,1 -k2,2 -k3,3 | tail -n 1 | awk '{ print $4 }'
}

floor_version=""
floor_state="unresolved"

resolve_floor() {
    [ "$floor_state" = "unresolved" ] || return 0
    [ -n "$FLOOR" ] || [ -n "$floor_override" ] \
        || stop "No floor: FLOOR is not set and \"$SETTINGS_FILE\" holds no FLOOR line in its settings block"
    if [ -n "$floor_override" ]; then
        floor_version="$floor_override"
        floor_state="ready"
        [ "$floor_version" != "$project_version" ] || floor_state="at-floor"
    elif [ "$(printf '%s\n' "$project_version" | cut -d . -f 1,2)" = "$FLOOR" ]; then
        floor_state="at-floor"
    else
        floor_version="$(newest_installed_editor "$FLOOR")"
        floor_state="ready"
        [ -n "$floor_version" ] || floor_state="missing"
    fi
}

canary_version=""
canary_resolved="false"
canary_lines=()

resolve_canary() {
    [ "$canary_resolved" = "false" ] || return 0
    canary_resolved="true"
    [ -n "$CANARY_EDITOR" ] \
        || stop "No canary editor: CANARY_EDITOR is empty; set it to a major and minor such as 6000.7, or unset it"
    canary_version="$(newest_installed_editor "$CANARY_EDITOR")"
}

opening="run-local-tests: $project_name on $project_version at ${head_commit:0:12}"
[ -z "$base" ] || opening="$opening against $base"
for job in "${selected[@]}"; do
    case "$job" in
        floor-*)
            resolve_floor
            case "$floor_state" in
                ready) opening="$opening; throwaway copy \"$(copy_folder "$floor_version")\" on $floor_version" ;;
                at-floor) opening="$opening; the project's editor is at the floor ${floor_override:-$FLOOR}" ;;
                missing) opening="$opening; no editor of the floor $FLOOR is installed" ;;
            esac
            break
            ;;
        canary-*)
            resolve_canary
            if [ -z "$canary_version" ]; then
                opening="$opening; no editor of the canary $CANARY_EDITOR is installed"
            elif [ "$job" = "canary-beta" ]; then
                opening="$opening; throwaway copy \"$(copy_folder "$canary_version" "$canary_root")\""
                opening="$opening without Library on $canary_version"
            else
                opening="$opening; the canary editor $canary_version"
            fi
            break
            ;;
    esac
done
say "$opening"
if [ -n "$working_changes" ]; then
    say "The working tree has changes to tracked files, so this partial run attests no commit."
fi

ensure_editor() {
    if [ -n "$editor_pid" ] && editor_alive "$editor_pid"; then
        return 0
    fi
    if [ -n "$launched_pid" ] && ! editor_alive "$launched_pid"; then
        launched_pid=""
    fi
    editor_pid="$(editor_pid_for "$project")"
    if [ -n "$editor_pid" ]; then
        editor_log="$(editor_log_of "$editor_pid")"
        return 0
    fi

    local executable child child_pid deadline
    executable="$(editor_executable "$project_version")"
    [ -n "$executable" ] \
        || stop "The project's editor $project_version is not installed: unity install $project_version"
    editor_log="$WORK_FOLDER/editor.log"
    say "opening $project_name headless in $project_version, log \"$editor_log\""
    "$executable" -batchmode -nographics -projectPath "$(native_path "$project")" \
        -logFile "$(native_path "$editor_log")" > /dev/null 2>&1 &
    child="$!"
    deadline=$((SECONDS + EDITOR_START_TIMEOUT_SECONDS))
    until [ -n "$editor_pid" ] && unity command --pid "$editor_pid" editor_status > /dev/null 2>&1; do
        kill -0 "$child" 2>/dev/null || stop "The editor exited while opening the project: see \"$editor_log\""
        [ "$SECONDS" -lt "$deadline" ] \
            || stop "The editor did not answer in $EDITOR_START_TIMEOUT_SECONDS s: see \"$editor_log\""
        sleep "$POLL_SECONDS"
        child_pid="$(process_id_of "$child")"
        if [ -z "$launched_pid" ] && [ "$(editor_pid_for "$project")" = "$child_pid" ]; then
            launched_pid="$child_pid"
            editor_pid="$child_pid"
        fi
    done
}

operation_word=""
operation_text=""

operation() {
    local output code=0
    ensure_editor
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
    printf '%s\n' "$operation_text" >> "$WORK_FOLDER/$current_job.txt"
}

operation_summary() {
    printf '%s\n' "$operation_text" | head -n 1 | sed 's/^[a-z-]*: *//'
}

table_rows="$WORK_FOLDER/table-rows.txt"
: > "$table_rows"
current_job=""
job_started=0

finish() {
    local seconds=$((SECONDS - job_started))
    say "$1: $current_job $2 ($seconds s)"
    printf '%s\t%s\t%s\t%s\n' "$current_job" "$1" "$seconds" "$2" >> "$table_rows"
    job_started="$SECONDS"
}

changed_matching() {
    printf '%s\n' "$changed" | grep -E "$1" || true
}

status_word() {
    sed -n 's/^ *"status": *"\([a-z]*\)".*/\1/p' "$1" | head -n 1
}

count_field() {
    sed -n "s/^ *\"$1\": *\([0-9]*\).*/\1/p" "$2" | head -n 1
}

result_attribute() {
    { grep -o '<test-run [^>]*>' "$2" || true; } | head -n 1 | sed -n "s/.* $1=\"\([0-9]*\)\".*/\1/p"
}

failed_names() {
    awk '/"FullName":/ { name = $0 } /"Status": *"Failed"/ { print name }' "$1" \
        | sed 's/.*"FullName": *"\(.*\)".*/    \1/; s/\\"/"/g'
}

finish_counts() {
    local total="$1" passed="$2" failed="$3" skipped="$4" source="$5" extra="${6:-}"
    if [ -z "$total" ] || [ -z "$failed" ]; then
        finish failed "the result file could not be read: \"$source\""
    elif [ "$failed" -eq 0 ] && [ -z "$extra" ]; then
        finish succeeded "$total tests, $passed passed, $failed failed, $skipped skipped"
    else
        finish failed "$total tests, $passed passed, $failed failed, $skipped skipped${extra:+, $extra}"
    fi
}

finish_from_results() {
    local results="$1" extra="${2:-}"
    finish_counts "$(result_attribute total "$results")" "$(result_attribute passed "$results")" \
        "$(result_attribute failed "$results")" "$(result_attribute skipped "$results")" "$results" "$extra"
}

editor_tests() {
    local mode="$1" status_file="$project/Temp/pipeline_test_status.json" started log_mark=0 output code=0
    ensure_editor
    if [ -f "$status_file" ] && [ "$(status_word "$status_file")" = "running" ]; then
        finish failed "a test run is in progress in this editor ($status_file says running)"
        return
    fi
    started="$(date +%s)"
    if [ -n "$editor_log" ] && [ -f "$editor_log" ]; then
        log_mark="$(wc -l < "$editor_log")"
    fi
    output="$(unity command --pid "$editor_pid" run_tests --mode "$mode" --async_tests true --result-only 2>&1)" \
        || code=$?
    printf '%s\n' "$output" > "$WORK_FOLDER/$current_job-start.txt"
    if [ "$code" -ne 0 ]; then
        finish failed "run_tests did not start, exit $code: see \"$WORK_FOLDER/$current_job-start.txt\""
        return
    fi

    local deadline=$((SECONDS + TEST_TIMEOUT_SECONDS)) saved="" status
    while [ "$SECONDS" -lt "$deadline" ]; do
        sleep "$POLL_SECONDS"
        if [ -f "$status_file" ] && [ "$(modified_seconds "$status_file")" -gt "$started" ]; then
            status="$(status_word "$status_file")"
            case "$status" in
                running) ;;
                completed)
                    cp "$status_file" "$WORK_FOLDER/$current_job-status.json"
                    finish_counts "$(count_field total "$status_file")" "$(count_field passed "$status_file")" \
                        "$(count_field failed "$status_file")" "$(count_field skipped "$status_file")" "$status_file"
                    failed_names "$WORK_FOLDER/$current_job-status.json"
                    return
                    ;;
                *)
                    finish failed "the run ended with the status \"$status\" in $status_file"
                    return
                    ;;
            esac
        fi
        if [ "$mode" = "PlayMode" ] && [ -n "$editor_log" ] && [ -f "$editor_log" ]; then
            saved="$(tail -n +"$((log_mark + 1))" "$editor_log" | tr -d '\r' \
                | sed -n 's/^Saving results to: //p' | tail -n 1)"
        fi
        if [ -n "$saved" ] && [ -f "$(posix_path "$saved")" ]; then
            cp "$(posix_path "$saved")" "$WORK_FOLDER/$current_job-results.xml"
            finish_from_results "$WORK_FOLDER/$current_job-results.xml"
            return
        fi
        if ! editor_alive "$editor_pid"; then
            finish failed "the editor, process $editor_pid, exited during the run: see \"$editor_log\""
            return
        fi
    done
    finish failed "no result in $TEST_TIMEOUT_SECONDS s: neither $status_file nor a results file in \"$editor_log\""
}

compile_settled() {
    local deadline=$((SECONDS + COMPILE_TIMEOUT_SECONDS)) answer
    ensure_editor
    while [ "$SECONDS" -lt "$deadline" ]; do
        answer="$(unity command --pid "$editor_pid" recompile_status --result-only 2>/dev/null || true)"
        if printf '%s\n' "$answer" | grep -qE '"status": *"idle"'; then
            unity command --pid "$editor_pid" recompile > /dev/null 2>&1 || true
        elif printf '%s\n' "$answer" | grep -qE '"status": *"(up_to_date|completed)"' \
            && unity command --pid "$editor_pid" editor_status --result-only 2>/dev/null \
                | tr -d '\n' | grep -qE '"compiling": *false, *"domainReloadInProgress": *false'; then
            return 0
        fi
        sleep "$POLL_SECONDS"
    done
    finish failed "the editor's compile did not settle in $COMPILE_TIMEOUT_SECONDS s"
    return 1
}

job_tests_edit() {
    compile_settled || return 0
    editor_tests EditMode
}

job_tests_play() {
    editor_tests PlayMode
}

job_packagecheck_check() {
    if [ -z "$package_name" ]; then
        finish skipped "the project holds no package under Packages/"
        return
    fi
    compile_settled || return 0
    operation "packagecheck check --path \"Packages/$package_name\""
    finish "$operation_word" "$(operation_summary)"
}

job_packagecheck_surface() {
    if [ -z "$package_name" ]; then
        finish skipped "the project holds no package under Packages/"
        return
    fi
    operation "core help --group packagecheck"
    if ! printf '%s\n' "$operation_text" | grep -q 'packagecheck surface'; then
        finish skipped "packagecheck surface does not exist yet (PackageCheck#27)"
        return
    fi
    operation "packagecheck surface --path \"Packages/$package_name\""
    finish "$operation_word" "$(operation_summary)"
}

job_core_ledger() {
    local triggers
    if [ -z "$base" ]; then
        finish failed "no base branch: none of ${BASE_BRANCHES[*]} exists, pass --base <branch>"
        return
    fi
    triggers="$(changed_matching '(^|/)ProjectSettings/ProjectVersion\.txt$|(^|/)manifest\.json$')"
    if [ -z "$triggers" ]; then
        finish skipped "no ProjectVersion.txt or manifest.json changed against $base"
        return
    fi
    operation "core unity-ledger"
    finish "$operation_word" "$(operation_summary)"
}

job_core_validate() {
    local definitions
    if [ -z "$base" ]; then
        finish failed "no base branch: none of ${BASE_BRANCHES[*]} exists, pass --base <branch>"
        return
    fi
    definitions="$(changed_matching "^(Assets|Packages/${package_name:-none})/.*\.asset$")"
    if [ -z "$definitions" ]; then
        finish skipped "no .asset under Assets or the package changed against $base"
        return
    fi
    if printf '%s\n' "$definitions" | grep -q '^Assets/'; then
        operation "core validate"
    else
        operation "core validate --path \"Packages/$package_name\""
    fi
    finish "$operation_word" "$(operation_summary)"
}

job_artpipeline_check() {
    local models model count=0 failures=0
    if [ -z "$base" ]; then
        finish failed "no base branch: none of ${BASE_BRANCHES[*]} exists, pass --base <branch>"
        return
    fi
    models="$(printf '%s\n' "$changed" | grep -iE '\.(fbx|obj|blend)$' || true)"
    if [ -z "$models" ]; then
        finish skipped "no model changed against $base"
        return
    fi
    operation "core help"
    if ! printf '%s\n' "$operation_text" | grep -qE '^artpipeline[: (]'; then
        finish skipped "the artpipeline group is not installed"
        return
    fi
    while IFS= read -r model; do
        [ -n "$model" ] || continue
        count=$((count + 1))
        operation "artpipeline check --path \"$model\""
        if [ "$operation_word" != "succeeded" ]; then
            failures=$((failures + 1))
            say "    \"$model\": $(operation_summary)"
        fi
    done <<< "$models"
    if [ "$failures" -eq 0 ]; then
        finish succeeded "$count models, 0 failed"
    else
        finish failed "$count models, $failures failed"
    fi
}

prepare_copy() {
    local version="$1" copy code=0
    copy="$(copy_folder "$version" "${2:-}")"
    mkdir -p "$copy"
    copies_made="true"
    if command -v robocopy > /dev/null 2>&1 && command -v cygpath > /dev/null 2>&1; then
        local source
        source="$(cygpath -w "$project")"
        MSYS_NO_PATHCONV=1 robocopy "$source" "$(cygpath -w "$copy")" /MIR \
            /XD "$source\\Library" "$source\\Temp" "$source\\Logs" "$source\\obj" "$source\\UserSettings" \
            "$source\\.git" /XF "$source\\.git" "*.sln" "*.csproj" /R:1 /W:1 /NFL /NDL /NJH /NJS /NP \
            > "$WORK_FOLDER/copy-$version.log" 2>&1 || code=$?
        [ "$code" -lt 8 ] \
            || stop "The copy to \"$copy\" failed, robocopy exit $code: see \"$WORK_FOLDER/copy-$version.log\""
    else
        rsync -a --delete --exclude /Library --exclude /Temp --exclude /Logs --exclude /obj --exclude /UserSettings \
            --exclude /.git --exclude '/*.sln' --exclude '/*.csproj' "$project/" "$copy/" \
            > "$WORK_FOLDER/copy-$version.log" 2>&1
    fi
    rm -rf "$copy/Library"
    printf 'm_EditorVersion: %s\n' "$version" > "$copy/ProjectSettings/ProjectVersion.txt"
}

floor_editor() {
    resolve_floor
    case "$floor_state" in
        at-floor)
            finish skipped \
                "not applicable: the project's editor $project_version is at the floor ${floor_override:-$FLOOR}"
            return 1
            ;;
        missing)
            finish failed "no editor of the floor $FLOOR is installed: unity install $FLOOR"
            return 1
            ;;
    esac
    floor_executable="$(editor_executable "$floor_version")"
    if [ -z "$floor_executable" ]; then
        finish failed "$floor_version is not installed: unity install $floor_version"
        return 1
    fi
    close_launched_editor
    prepare_copy "$floor_version"
}

compile_code=0
compile_errors=0
compile_first=""
compile_broke=""
compile_warning_count=0
compile_warnings=""

compile_copy() {
    local executable="$1" copy="$2" log="$3" readings
    compile_code=0
    rm -f "$log"
    with_timeout "$FLOOR_TIMEOUT_SECONDS" "$executable" -batchmode -nographics -quit \
        -projectPath "$(native_path "$copy")" -logFile "$(native_path "$log")" > /dev/null 2>&1 || compile_code=$?
    readings=""
    [ ! -f "$log" ] || readings="$(awk '
        { sub(/\r$/, "") }
        in_block && /^[ \t]/ {
            text = $0
            sub(/^[ \t]+/, "", text)
            if (block_first == "") block_first = text
            if (broke == "" && text ~ /cannot be found/) broke = text
            next
        }
        in_block { in_block = 0; block_seen = 1 }
        !block_seen && /An error occurred while resolving packages/ { in_block = 1; next }
        /error CS[0-9]+/ {
            text = $0
            sub(/^[ \t]+/, "", text)
            key = text
            if (match(text, /\([0-9]+,[0-9]+\): error CS[0-9]+/)) {
                part = substr(text, RSTART + 1, RLENGTH - 1)
                sub(/,[0-9]+\): error /, " ", part)
                key = substr(text, 1, RSTART - 1) " " part
            }
            if (!(key in errors)) {
                errors[key] = 1
                error_count++
                if (first == "") first = text
            }
        }
        /warning UAC[0-9]+/ {
            text = $0
            sub(/^[ \t]+/, "", text)
            match(text, /warning UAC[0-9]+/)
            code = substr(text, RSTART + 8, RLENGTH - 8)
            key = code " " text
            if (match(text, /\([0-9]+,[0-9]+\): warning UAC/)) {
                part = substr(text, RSTART + 1, RLENGTH - 1)
                sub(/,.*/, "", part)
                key = code " " substr(text, 1, RSTART - 1) " " part
            }
            if (!(key in warnings)) {
                warnings[key] = 1
                per_code[code]++
                warning_count++
            }
        }
        END {
            if (broke == "") broke = block_first
            printf "errors=%d\nfirst=%s\nbroke=%s\nwarnings=%d\n", error_count, first, broke, warning_count
            for (code in per_code) printf "code=    %s x%d\n", code, per_code[code]
        }' "$log")"
    compile_errors="$(sed -n 's/^errors=//p' <<< "$readings")"
    compile_errors="${compile_errors:-0}"
    compile_first="$(sed -n 's/^first=//p' <<< "$readings")"
    compile_broke="$(sed -n 's/^broke=//p' <<< "$readings")"
    compile_warning_count="$(sed -n 's/^warnings=//p' <<< "$readings")"
    compile_warning_count="${compile_warning_count:-0}"
    compile_warnings="$(sed -n 's/^code=//p' <<< "$readings")"
    [ -z "$compile_warnings" ] || compile_warnings="$(sort <<< "$compile_warnings")"
}

job_floor_compile() {
    local log
    floor_editor || return 0
    log="$WORK_FOLDER/floor-compile-$floor_version.log"
    compile_copy "$floor_executable" "$(copy_folder "$floor_version")" "$log"
    if [ "$compile_errors" -eq 0 ] && [ "$compile_code" -eq 0 ]; then
        finish succeeded "$floor_version: 0 error CS, log \"$log\""
    elif [ "$compile_errors" -eq 0 ]; then
        finish failed "$floor_version: 0 error CS, exit $compile_code, log \"$log\""
    else
        finish failed \
            "$floor_version: $compile_errors error CS, the first: $compile_first; exit $compile_code, log \"$log\""
    fi
}

failed_cases() {
    { grep -o '<test-case [^>]*result="Failed"[^>]*>' "$1" || true; } \
        | sed -n 's/.* fullname="\([^"]*\)".*/    \1/p'
}

job_floor_tests() {
    local modes=(EditMode) mode results output code counts failed_count summary="" word="succeeded"
    floor_editor || return 0
    if [ -n "$package_name" ] && [ -d "$project/Packages/$package_name/Tests/Runtime" ]; then
        modes+=(PlayMode)
    fi
    for mode in "${modes[@]}"; do
        results="$WORK_FOLDER/floor-tests-$floor_version-$mode.xml"
        output="$WORK_FOLDER/floor-tests-$floor_version-$mode.txt"
        rm -f "$results"
        code=0
        unity test "$(native_path "$(copy_folder "$floor_version")")" --mode "$mode" \
            --output "$(native_path "$results")" --timeout "$FLOOR_TIMEOUT_SECONDS" > "$output" 2>&1 || code=$?
        if [ ! -f "$results" ]; then
            word="failed"
            counts="no result file, exit $code: see \"$output\""
        elif [ -z "$(result_attribute total "$results")" ]; then
            word="failed"
            counts="the result file could not be read: \"$results\""
        else
            failed_count="$(result_attribute failed "$results")"
            counts="$(result_attribute total "$results") tests, $(result_attribute passed "$results") passed,"
            counts="$counts ${failed_count:-unknown} failed,"
            counts="$counts $(result_attribute inconclusive "$results") inconclusive,"
            counts="$counts $(result_attribute skipped "$results") skipped"
            if [ "${failed_count:-1}" -ne 0 ] || [ "$code" -ne 0 ]; then
                word="failed"
                [ "$code" -eq 0 ] || counts="$counts, exit $code"
            fi
        fi
        summary="${summary:+$summary; }$mode $counts"
    done
    finish "$word" "$floor_version: $summary"
    for mode in "${modes[@]}"; do
        [ ! -f "$WORK_FOLDER/floor-tests-$floor_version-$mode.xml" ] \
            || failed_cases "$WORK_FOLDER/floor-tests-$floor_version-$mode.xml"
    done
}

job_soak() {
    finish skipped "the soak does not exist yet (R7b)"
}

canary_editor() {
    resolve_canary
    if [ -z "$canary_version" ]; then
        finish skipped "not run: no editor of the canary $CANARY_EDITOR is installed: unity install $CANARY_EDITOR"
        return 1
    fi
    canary_executable="$(editor_executable "$canary_version")"
    if [ -z "$canary_executable" ]; then
        finish skipped "not run: $canary_version is not installed: unity install $canary_version"
        return 1
    fi
}

tree_changed() {
    [ -z "$working_changes" ] || return 0
    [ -n "$(git -C "$project" ls-files --others --exclude-standard -- Assets Packages ProjectSettings scripts)" ]
}

canary_post() {
    local context="unity-$current_job" description line escaped="'\\''"
    if tree_changed; then
        canary_lines+=("$context: no post line: the working tree has changes")
        return
    fi
    description="${2:0:$CANARY_DESCRIPTION_LIMIT}"
    description="${description//\'/$escaped}"
    line="bash scripts/post-status.sh --sha $head_commit --state $1 --context $context"
    line="$line --description '$description' --report \"$WORK_FOLDER/$current_job.txt\""
    canary_lines+=("$line")
}

job_canary_beta() {
    local log description summary state="success"
    canary_editor || return 0
    close_launched_editor
    prepare_copy "$canary_version" "$canary_root"
    log="$WORK_FOLDER/canary-beta-$canary_version.log"
    compile_copy "$canary_executable" "$(copy_folder "$canary_version" "$canary_root")" "$log"
    description="$canary_version: $compile_errors error CS, $compile_warning_count UAC warnings"
    if [ "$compile_errors" -eq 0 ] && [ "$compile_code" -eq 0 ]; then
        summary="$description, log \"$log\""
    elif [ "$compile_errors" -eq 0 ]; then
        state="failure"
        description="$description, exit $compile_code"
        [ -z "$compile_broke" ] || description="$canary_version: 0 error CS, exit $compile_code, $compile_broke"
        summary="$description, log \"$log\""
    else
        state="failure"
        summary="$description, the first: $compile_first; exit $compile_code, log \"$log\""
    fi
    if [ "$state" = "success" ]; then
        finish succeeded "$summary"
    else
        finish failed "$summary"
    fi
    printf '%s\n' "$summary" >> "$WORK_FOLDER/$current_job.txt"
    if [ -n "$compile_warnings" ]; then
        say "$compile_warnings"
        printf '%s\n' "$compile_warnings" >> "$WORK_FOLDER/$current_job.txt"
    fi
    canary_post "$state" "$description"
}

job_canary_coreclr() {
    local variations folder install found=""
    canary_editor || return 0
    variations="$(dirname "$canary_executable")/Data/PlaybackEngines/windowsstandalonesupport/Variations"
    for folder in "$variations"/*; do
        if [ -d "$folder" ] && basename "$folder" | grep -qi 'coreclr'; then
            found="$folder"
            break
        fi
    done
    if [ -z "$found" ]; then
        install="unity install-modules --editor-version $canary_version -m windows-coreclr"
        finish skipped "not run: the CoreCLR player module is not installed for $canary_version: $install"
        return
    fi
    finish succeeded "present: \"$found\""
    printf '%s\n' "present: \"$found\"" >> "$WORK_FOLDER/$current_job.txt"
    canary_post success "$canary_version: the CoreCLR player module is present"
}

for current_job in "${selected[@]}"; do
    : > "$WORK_FOLDER/$current_job.txt"
    job_started="$SECONDS"
    "job_${current_job//-/_}"
done

table="$WORK_FOLDER/table.txt"
{
    printf '%-20s %-10s %8s  %s\n' job status seconds summary
    awk -F '\t' '{ printf "%-20s %-10s %8s  %s\n", $1, $2, $3, $4 }' "$table_rows"
} > "$table"
say ""
cat "$table"

gate_rows="$(awk -F '\t' -v canaries=" ${CANARIES[*]} " 'index(canaries, " " $1 " ") == 0' "$table_rows")"
ran="$(printf '%s\n' "$gate_rows" | awk -F '\t' 'NF && $2 != "skipped"' | wc -l | tr -d ' ')"
failed_jobs="$(printf '%s\n' "$gate_rows" | awk -F '\t' 'NF && $2 != "skipped" && $2 != "succeeded"' | wc -l \
    | tr -d ' ')"
state="success"
[ "$failed_jobs" -eq 0 ] || state="failure"
say ""
if [ "$gate_selected" = "false" ]; then
    [ "${#canary_lines[@]}" -gt 0 ] || say "No post-status.sh line: no canary ran."
elif [ -n "$only" ]; then
    say "No post-status.sh line: --only ran part of the gate, and a status attests a run of every job."
elif [ "$ran" -eq 0 ]; then
    say "No post-status.sh line: no job ran."
else
    say "bash scripts/post-status.sh --sha $head_commit --state $state --context unity-tests" \
        "--description \"$ran jobs, $failed_jobs failed\" --report \"$table\""
fi
for line in ${canary_lines[@]+"${canary_lines[@]}"}; do
    say "$line"
done
[ "$state" = "success" ]

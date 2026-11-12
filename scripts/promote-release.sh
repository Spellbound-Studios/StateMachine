#!/usr/bin/env bash
set -euo pipefail

REMOTE="${REMOTE-origin}"
STATUS_CONTEXT="${STATUS_CONTEXT-strangers}"
RELEASE_WORKFLOW="${RELEASE_WORKFLOW-release.yml}"
RELEASE_WRITTEN_PATTERN="${RELEASE_WRITTEN_PATTERN-^Packages/[^/]+/(package\.json|CHANGELOG\.md)$}"

usage() {
    cat >&2 <<'TEXT'
usage: bash scripts/promote-release.sh <rc|main|sync> [--dry-run]

Promotes a package's release by a merge, for a person to run in the package's repository. Each released
branch carries its own release commit, so a promotion merges the source branch into a local copy of the
target with --no-ff and pushes that merge, and the push starts the target's release run; a target that does
not exist yet starts from main, so its first push is a merge too. rc merges beta when
beta's head carries the newest -beta.N tag and beta holds main's last release; main merges rc when rc's head
carries a strangers status in state success, and the push to the protected main needs an organisation
owner, the ruleset's bypass; sync merges main into beta after a final release, because the release refuses a
beta below main's last release. The working tree must be clean; a conflict in the package's package.json or
CHANGELOG.md takes the target's side, because the release rewrites both there, and any other conflict aborts
the merge and is refused; a push that is not a merge on top of the target's head is refused. The script fetches, prints
every check, merges, pushes and returns to the branch it started on. --dry-run reads the remote without
fetching and prints the commands instead of running them.
TEXT
}

say() {
    printf '%s\n' "$*"
}

target=""
mode=""
dry_run="false"
while [ "$#" -gt 0 ]; do
    case "$1" in
        rc|main|sync)
            [ -z "$mode" ] || { usage; exit 2; }
            mode="$1"
            shift
            ;;
        --dry-run) dry_run="true"; shift ;;
        *) usage; exit 2 ;;
    esac
done
[ -n "$mode" ] || { usage; exit 2; }

case "$mode" in
    rc) source_branch="beta"; target="rc" ;;
    main) source_branch="rc"; target="main" ;;
    sync) source_branch="main"; target="beta" ;;
esac

refusals=0
refuse() {
    say "refused: $*"
    refusals=$((refusals + 1))
}

git rev-parse --show-toplevel > /dev/null 2>&1 || { say "failed: $(pwd) is not inside a git repository"; exit 1; }
remote_address="$(git remote get-url "$REMOTE" 2>/dev/null)" \
    || { say "failed: this repository has no remote called $REMOTE"; exit 1; }
repository="$(printf '%s\n' "$remote_address" | sed 's|\.git$||; s|^.*[:/]\([^/:]*/[^/]*\)$|\1|')"

error_file="$(mktemp)"
starting_branch=""
return_to_start() {
    [ -n "$starting_branch" ] || return 0
    git checkout --quiet "$starting_branch" || say "failed: returning to $starting_branch failed; check it out by hand"
    starting_branch=""
}
finish_run() {
    return_to_start
    rm -f "$error_file"
}
trap finish_run EXIT

remote_failed() {
    say "failed: reading $REMOTE failed: $(head -n 1 "$error_file")"
    exit 1
}

if [ "$dry_run" = "true" ]; then
    say "dry run: $REMOTE ($repository) is read with git ls-remote and nothing is fetched"
else
    git fetch --quiet --tags "$REMOTE" 2>"$error_file" || remote_failed
    say "checked: fetched $REMOTE ($repository)"
fi

working_changes="$(git status --porcelain)"
if [ -z "$working_changes" ]; then
    say "checked: the working tree is clean"
else
    refuse "the working tree has changes; commit or stash them, then run this again"
fi

heads="$(git ls-remote --heads "$REMOTE" 2>"$error_file")" || remote_failed
tags="$(git ls-remote --tags "$REMOTE" 2>"$error_file")" || remote_failed
head_of() {
    printf '%s\n' "$heads" | awk -v ref="refs/heads/$1" '$2 == ref { print $1 }'
}

source_head="$(head_of "$source_branch")"
target_head="$(head_of "$target")"
main_head="$(head_of main)"

tag_commits="$(printf '%s\n' "$tags" | awk '
    $2 ~ /^refs\/tags\// {
        name = substr($2, 11)
        if (name ~ /\^\{\}$/) { name = substr(name, 1, length(name) - 3); peeled[name] = $1 }
        else if (!(name in direct)) { direct[name] = $1 }
    }
    END { for (name in direct) print name, (name in peeled ? peeled[name] : direct[name]) }')"

newest_tag() {
    printf '%s\n' "$tag_commits" | awk -v kind="$1" '
        {
            if (kind == "") pattern = "^v[0-9]+\\.[0-9]+\\.[0-9]+$"
            else pattern = "^v[0-9]+\\.[0-9]+\\.[0-9]+-" kind "\\.[0-9]+$"
            if ($1 !~ pattern) next
            split(substr($1, 2), parts, /[.-]/)
            print parts[1], parts[2], parts[3], (kind == "" ? 0 : parts[5]), $1, $2
        }' | sort -n -k1,1 -k2,2 -k3,3 -k4,4 | tail -n 1 | awk '{ print $5, $6 }'
}

present() {
    git cat-file -e "$1^{commit}" 2>/dev/null
}

contains() {
    if ! present "$1" || ! present "$2"; then
        return 2
    fi
    git merge-base --is-ancestor "$1" "$2"
}

source_tag=""
if [ -z "$source_head" ]; then
    case "$mode" in
        rc) refuse "$REMOTE has no beta branch yet; the first release cuts it from main" \
            "(git push $REMOTE main:refs/heads/beta, after the App's two secrets are set), and rc follows once" \
            "a -beta.N release ran on it" ;;
        main) refuse "$REMOTE has no rc branch yet; promote beta to rc first with bash scripts/promote-release.sh rc" ;;
        sync) refuse "$REMOTE has no main branch" ;;
    esac
else
    say "checked: $REMOTE/$source_branch is at $source_head"
fi

if [ -n "$source_head" ] && [ "$mode" != "sync" ]; then
    read -r source_tag source_tag_commit <<< "$(newest_tag "$source_branch")" || true
    if [ -z "$source_tag" ]; then
        refuse "$REMOTE holds no -$source_branch.N tag, so no release ran on $source_branch; watch it with" \
            "gh run list --workflow $RELEASE_WORKFLOW --branch $source_branch"
    elif [ "$source_tag_commit" != "$source_head" ]; then
        refuse "$REMOTE/$source_branch's head carries no release tag (the newest -$source_branch.N is" \
            "$source_tag on $source_tag_commit); wait for the release on $source_branch:" \
            "gh run list --workflow $RELEASE_WORKFLOW --branch $source_branch"
    else
        say "checked: $REMOTE/$source_branch's head carries $source_tag, the newest -$source_branch.N tag"
    fi
fi

if [ "$mode" = "rc" ] && [ -n "$source_head" ] && [ -n "$main_head" ]; then
    read -r final_tag final_tag_commit <<< "$(newest_tag "")" || true
    if [ -z "$final_tag" ]; then
        say "checked: $REMOTE holds no final release tag, so beta has none to take from main"
    else
        on_main=0
        contains "$final_tag_commit" "$main_head" || on_main=$?
        on_beta=0
        contains "$final_tag_commit" "$source_head" || on_beta=$?
        if [ "$on_main" -eq 2 ] || [ "$on_beta" -eq 2 ]; then
            say "not checked: whether beta holds main's $final_tag needs the commits here; the run without" \
                "--dry-run fetches them first"
        elif [ "$on_main" -eq 0 ] && [ "$on_beta" -ne 0 ]; then
            refuse "$REMOTE/main carries $final_tag and beta does not contain it; merge main into beta first:" \
                "bash scripts/promote-release.sh sync"
        elif [ "$on_beta" -eq 0 ]; then
            say "checked: beta contains $final_tag, main's last release"
        else
            say "not checked: $final_tag, the newest final tag, is on neither main nor beta"
        fi
    fi
fi

if [ "$mode" = "main" ] && [ -n "$source_head" ]; then
    status_code=0
    state="$(gh api "repos/$repository/commits/$source_head/status" \
        --jq ".statuses[] | select(.context == \"$STATUS_CONTEXT\") | .state" 2>"$error_file")" \
        || status_code=$?
    state="$(printf '%s\n' "$state" | head -n 1)"
    if [ "$status_code" -ne 0 ]; then
        say "failed: reading the $STATUS_CONTEXT status of $source_head failed, gh exit $status_code:" \
            "$(head -n 1 "$error_file")"
        exit 1
    elif [ "$state" = "success" ]; then
        say "checked: $source_head carries the $STATUS_CONTEXT status in state success"
    else
        refuse "$source_head carries the $STATUS_CONTEXT status in state '${state:-none}', not success; run the" \
            "strangers against the candidate first: bash scripts/run-strangers.sh ${source_tag:-<rc tag>}"
    fi
fi

if [ "$mode" = "sync" ] && [ -n "$source_head" ] && [ -z "$target_head" ]; then
    refuse "$REMOTE has no beta branch; the first release cuts it from main (git push $REMOTE main:refs/heads/beta)"
fi

if [ -n "$source_head" ] && [ -n "$target_head" ]; then
    held=0
    contains "$source_head" "$target_head" || held=$?
    if [ "$held" -eq 0 ]; then
        say "succeeded: $REMOTE/$target already contains $REMOTE/$source_branch at $source_head, nothing to merge"
        exit 0
    elif [ "$held" -eq 2 ]; then
        say "not checked: whether $target already contains $source_branch needs the commits here; the run" \
            "without --dry-run fetches them first"
    fi
fi

base_ref=""
base_head=""
if [ -n "$target_head" ]; then
    base_ref="$REMOTE/$target"
    base_head="$target_head"
elif [ "$mode" != "sync" ]; then
    base_ref="$REMOTE/main"
    base_head="$main_head"
    if [ -n "$main_head" ]; then
        say "checked: $REMOTE has no $target branch yet, so it starts from $REMOTE/main at $main_head and" \
            "$source_branch is merged into it"
    else
        refuse "$REMOTE has no main branch to start $target from"
    fi
fi

local_head="$(git rev-parse --verify --quiet "refs/heads/$target" || true)"
reset_to="${base_head:-$source_head}"
if [ -n "$local_head" ] && [ -n "$reset_to" ]; then
    kept=0
    contains "$local_head" "$reset_to" || kept=$?
    if [ "$kept" -eq 0 ]; then
        say "checked: the local branch $target holds nothing $REMOTE/$target lacks"
    elif [ "$kept" -eq 2 ]; then
        say "not checked: whether the local branch $target is behind $REMOTE/$target needs the commits here;" \
            "the run without --dry-run fetches them first"
    else
        refuse "the local branch $target at $local_head holds commits $REMOTE/$target does not, and the" \
            "promotion resets it; push them or keep them under another name (git branch -m $target" \
            "$target-local), then run this again"
    fi
fi

if [ -n "$base_ref" ]; then
    commands=("git checkout -B $target $base_ref" "git merge --no-ff --no-edit $REMOTE/$source_branch"
        "git push $REMOTE $target")
else
    commands=("git checkout -B $target $REMOTE/$source_branch" "git push $REMOTE $target")
fi
command_list="$(printf '%s; ' "${commands[@]}")"
command_list="${command_list%; }"
if [ "$target" = "main" ]; then
    say "note: main is protected, so the push needs an organisation owner, the ruleset's bypass"
fi

expected_tag="the next release tag"
if [ -n "$source_tag" ]; then
    base_version="${source_tag%%-*}"
    if [ "$mode" = "rc" ]; then
        read -r newest_candidate _ <<< "$(newest_tag rc)" || true
        number=1
        case "$newest_candidate" in
            "$base_version-rc."*) number=$((${newest_candidate##*.} + 1)) ;;
        esac
        expected_tag="$base_version-rc.$number"
    else
        expected_tag="$base_version"
    fi
fi
watch="gh run list --workflow $RELEASE_WORKFLOW --branch $target"

if [ "$refusals" -gt 0 ]; then
    say "failed: $refusals checks refused merging $source_branch into $target; nothing was pushed" \
        "(the commands would be: $command_list)"
    exit 1
fi

if [ "$dry_run" = "true" ]; then
    say "previewed: $command_list; then the push starts the release on $target, which tags" \
        "$expected_tag ($watch)"
    exit 0
fi

[ "$(git rev-parse "$REMOTE/$source_branch")" = "$source_head" ] \
    || { say "failed: $REMOTE/$source_branch moved while the checks ran; run this again"; exit 1; }
starting_branch_name="$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)"

if [ -n "$base_ref" ]; then
    say "running: git checkout -B $target $base_ref"
    starting_branch="$starting_branch_name"
    git checkout --quiet -B "$target" "$base_ref"
    say "running: git merge --no-ff --no-edit $REMOTE/$source_branch"
    if ! git merge --no-ff --no-edit "$REMOTE/$source_branch"; then
        conflicts="$(git diff --name-only --diff-filter=U)"
        others="$(printf '%s\n' "$conflicts" | grep -Ev "$RELEASE_WRITTEN_PATTERN" | grep -v '^$' || true)"
        settled="true"
        if [ -z "$conflicts" ] || [ -n "$others" ]; then
            settled="false"
        else
            while IFS= read -r path; do
                if git checkout --ours -- "$path" && git add -- "$path"; then
                    say "settled: $path takes $target's side, which the release rewrites"
                else
                    settled="false"
                fi
            done <<< "$conflicts"
            [ "$settled" = "false" ] || git commit --quiet --no-edit || settled="false"
        fi
        if [ "$settled" = "false" ]; then
            git merge --abort 2>/dev/null || true
            say "failed: merging $source_branch into $target conflicts in" \
                "$(printf '%s\n' "${others:-$conflicts}" | tr '\n' ' '); the merge is aborted and nothing was pushed"
            exit 1
        fi
    fi
    if [ "$(git rev-parse HEAD^1)" != "$base_head" ] || [ "$(git rev-parse HEAD^2)" != "$source_head" ]; then
        say "failed: the result is not a merge of $source_branch on top of $base_ref; nothing was pushed"
        exit 1
    fi
else
    say "running: git checkout -B $target $REMOTE/$source_branch"
    starting_branch="$starting_branch_name"
    git checkout --quiet -B "$target" "$REMOTE/$source_branch"
fi

say "running: git push $REMOTE $target"
if ! git push "$REMOTE" "$target"; then
    say "failed: the push of $target was refused; nothing moved on $REMOTE"
    exit 1
fi
say "succeeded: $target holds $source_branch at $source_head; the release tags $expected_tag: $watch"

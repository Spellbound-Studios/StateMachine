#!/usr/bin/env bash
set -euo pipefail

DESCRIPTION_LIMIT=140
DRY_RUN="${DRY_RUN:-0}"

usage() {
    cat >&2 <<'TEXT'
usage: bash scripts/post-status.sh --sha <commit> --state <success|failure>
                                   --context <unity-tests|strangers|unity-canary-beta|unity-canary-coreclr>
                                   --description <text> [--report <file>] [--dry-run]

Posts a commit status on this checkout's repository, the way an author's local gate attests a commit:
run-local-tests.sh prints the line for unity-tests and run-strangers.sh the line for strangers. The gate's
canary rows print theirs for unity-canary-beta and unity-canary-coreclr, contexts no ruleset requires. --report
appends the first twelve characters of the report's SHA-256 to the description, so the status names the
report that produced it. A commit the current branch cannot reach is refused, and so is a description over
GitHub's 140 characters. --dry-run, or DRY_RUN set to anything but 0, prints the call instead of making it.
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

sha=""
state=""
context=""
description=""
report=""
dry_run="false"
case "$DRY_RUN" in
    ""|0) ;;
    *) dry_run="true" ;;
esac
while [ "$#" -gt 0 ]; do
    case "$1" in
        --sha) value_of "$#" "${2:-}"; sha="$2"; shift 2 ;;
        --state) value_of "$#" "${2:-}"; state="$2"; shift 2 ;;
        --context) value_of "$#" "${2:-}"; context="$2"; shift 2 ;;
        --description) value_of "$#" "${2:-}"; description="$2"; shift 2 ;;
        --report) value_of "$#" "${2:-}"; report="$2"; shift 2 ;;
        --dry-run) dry_run="true"; shift ;;
        *) usage; exit 2 ;;
    esac
done

if [ -z "$sha" ] || [ -z "$state" ] || [ -z "$context" ] || [ -z "$description" ]; then
    usage
    exit 2
fi

case "$state" in
    success|failure) ;;
    *) stop "The state is success or failure: $state" ;;
esac

case "$context" in
    unity-tests|strangers|unity-canary-beta|unity-canary-coreclr) ;;
    *) stop "The context is unity-tests, strangers, unity-canary-beta or unity-canary-coreclr: $context" ;;
esac

if [ -n "$report" ]; then
    [ -f "$report" ] || stop "No report at \"$report\""
    hash="$(sha256sum < "$report" | cut -c 1-12)"
    description="$description report:$hash"
fi

if [ "${#description}" -gt "$DESCRIPTION_LIMIT" ]; then
    stop "The description is ${#description} characters with its report suffix; GitHub takes $DESCRIPTION_LIMIT."
fi

root="$(git rev-parse --show-toplevel)"
cd "$root"

commit="$(git rev-parse --verify --quiet "$sha^{commit}" || true)"
[ -n "$commit" ] || stop "No commit $sha in this checkout: fetch it first"

branch="$(git rev-parse --abbrev-ref HEAD)"
if ! git merge-base --is-ancestor "$commit" HEAD; then
    stop "Refused: $commit is not reachable from $branch, so its status would attest work this branch does not hold"
fi

repository="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
[ -n "$repository" ] || stop "gh names no repository for this checkout"

if [ "$dry_run" = "true" ]; then
    say "gh api repos/$repository/statuses/$commit -f state=$state -f context=$context" \
        "-f \"description=$description\""
    exit 0
fi

gh api --silent "repos/$repository/statuses/$commit" -f "state=$state" -f "context=$context" \
    -f "description=$description"
say "posted: $state $context \"$description\" on $repository@$commit"

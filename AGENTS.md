# Working in this repository

## What is where

- The repository root is the Unity dev project.
- The package is `Packages/<Name>`. It is the only folder a consumer receives.
- `Assets/_Project` is scaffolding for the dev project and never ships.

## Starting a package from this template

1. `gh repo create Spellbound-Studios/<Name> --template Spellbound-Studios/Template --private --clone`
2. `bash scripts/initialise-package.sh <Name> "<the one-sentence job>"`, with `--kind tool`, `--requires burst,mathematics,urp` or `--presentation` as the sentence needs.
3. `bash scripts/setup.sh`, then open the folder in Unity Hub.

## Pull request titles

Format: `type(scope): what changed`

- Types: `feat fix perf refactor docs test build ci chore`
- Put a `!` before the colon for a breaking change, for example `feat(scope)!: what changed`.
- Pull requests are squash-merged with the title alone, so the title is the commit message.

## Versions

Never edit `version` in `package.json`. The release writes it.

## Checks

- Run `bash scripts/setup.sh` once after cloning.
- Before asking for review, run `bash scripts/run-local-tests.sh`, the local gate: it runs the Unity jobs listed at its top over the dev project (the tests in both modes, the bar, the ledger and validation checks the change calls for, and the floor editor's compile and tests on a throwaway copy), then prints the table and the `post-status.sh` line to type. `--only <job>` runs one job.
- The gate's two canary rows, `canary-beta` and `canary-coreclr`, run only on demand (`--canaries`, or `--only` with one of them) against the next Unity named by `CANARY_EDITOR`, print the line for their `unity-canary-beta` or `unity-canary-coreclr` status when the working tree is clean, and never change the gate's status.
- `bash scripts/post-status.sh` posts that line's `unity-tests` status on the commit, with the report's hash in its description; `--dry-run` prints the call instead.
- `bash scripts/run-strangers.sh <tag>` runs the stranger projects that install the package against a tag pushed to origin and prints the `strangers` status line the same way.
- `bash scripts/check.sh` runs the line rules that are a text match over the package, then the template's own checks; `--rule <id>` runs one.
- The settings block at the top of `check.sh` holds the studio's values on purpose, because this is the studio's Template; each setting reads an environment variable of the same name first.
- `bash scripts/check-line-text-pointer.sh` fails when a file copies the line text instead of pointing at it.
- `bash scripts/check-line-endings.sh` proves the `.gitattributes` rule: a file committed with LF comes back from a clone with CRLF and its byte order mark, and a shell script stays LF.

## Keeping the shell current

- `bash scripts/sync-template.sh` opens a pull request where a file named in `managed-files.txt` drifted from the template; `--check` only reports.
- `bash scripts/update-skeleton.sh` opens a pull request when PackageCheck's skeleton version moved past the one `skeleton-version.txt` records; that file is a record, never a held version.
- `bash scripts/repository-settings.sh Spellbound-Studios/<Name>` prints the lines that set the repository as every repository is set; `--check` reports drift and prints the organisation's Git LFS storage and downloads against the free 10 GB.

## Issues and the board

- Open issues through the forms. An agent writes the body with `bash scripts/render-issue-body.sh <kind> ...` and opens it with `gh issue create --type <Type>`.
- `bash scripts/sprint-report.sh` prints the current sprint from the board.

## Releasing

- Nobody types a version, edits the changelog or picks a tag name: the release writes the version in `package.json` and the entry in `CHANGELOG.md` from the pull request titles, and makes the tag.
- Pull requests land on `beta`, and each merge releases the next `-beta.N`.
- A person promotes `beta` to `rc` with `bash scripts/promote-release.sh rc`, which merges `beta` into `rc` and pushes the merge; the release tags `-rc.N`, which the strangers run against.
- A person promotes `rc` to `main` with `bash scripts/promote-release.sh main` only on a green `strangers` status; the merge is pushed by an organisation owner, the bypass of the protected `main`, and the release tags the final version.
- After a final release, `bash scripts/promote-release.sh sync` merges `main` into `beta`, because the release refuses a beta below main's last release; `rc` is refused until it has run.
- Each released branch carries its own release commit, so a promotion is a merge, never a fast-forward. `--dry-run` prints the checks and the commands without running them.
- Core's `v1.1.9` is the one tag made before releases came from commits: its baseline, so Core's rewrite releases as `2.0.0-beta.N`. Every other package's first release is `1.0.0-beta.1`.

## The rules

The binding rules are the line text at the address in `line-text-address.txt`. Nothing here copies them.

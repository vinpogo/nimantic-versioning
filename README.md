# nimantic-versioning

Semantic versioning for Nim projects, driven by [Conventional
Commits](https://www.conventionalcommits.org) and wired into Git via hooks.

Every commit is validated against the Conventional Commits format. When it
passes, a small note recording the resulting version bump (`major` / `minor`
/ `patch` / `none`) is folded into that same commit. Later, `bump` consolidates
all pending notes since the last release, bumps the `.nimble` file's version
by the *highest* bump level found (bumps don't stack), and writes a grouped
entry to `CHANGELOG.md`.

## Install

```sh
nimble install
```

This builds the `nimantic_versioning` binary and puts it on your Nimble
bin path, which needs to be on `PATH` for the Git hooks to find it.

## Setup (per repository)

From the root of the Git repository you want to version:

```sh
nimantic_versioning init
nimantic_versioning install-hooks
```

`init` creates `.nimantic-versioning/config.ini` (pre-populated with sensible
defaults, see below) and a `.nimantic-versioning/changes/` directory.
`install-hooks` writes a `commit-msg` and a `post-commit` hook into
`.git/hooks/` that delegate to this binary. Both `.nimantic-versioning/`
and its contents should be committed to Git — the pending change notes
need to survive across separate commits until you run `bump`.

## Everyday use

Just commit normally, using Conventional Commits syntax:

```
type(scope)!: subject

optional body

optional footer, e.g.:
BREAKING CHANGE: describe the break
```

- The `commit-msg` hook rejects the commit if the header doesn't parse, or if
  `type` isn't one of the types listed in `.nimantic-versioning/config.ini`.
- The `post-commit` hook then determines the bump level for the commit and
  records it under `.nimantic-versioning/changes/`, amending it into the
  commit that was just created so history stays tidy.
- A `!` after the type/scope (`feat!:`) or a `BREAKING CHANGE:` footer always
  forces a `major` bump, regardless of what the type is configured to do.

When you're ready to cut a release:

```sh
nimantic_versioning bump                       # updates .nimble + CHANGELOG.md, commits, and tags
nimantic_versioning bump --dry-run             # preview without writing anything
nimantic_versioning bump --no-commit           # update files, but skip the commit (and the tag)
nimantic_versioning bump --no-tag              # commit the release, but skip the git tag
nimantic_versioning bump --no-commit --no-tag  # only touch .nimble/CHANGELOG.md, no git activity
```

By default `bump` both creates a `version: vX.Y.Z` release commit and tags it
`vX.Y.Z`. Pass `--no-commit` and/or `--no-tag` to opt out of either. Tagging
requires a release commit to point at, so `--no-commit` alone (without
`--no-tag`) skips the tag too, with a message explaining why.

`bump` reads every pending file in `.nimantic-versioning/changes/`, takes the
highest bump level among them (major > minor > patch > none — levels are
never added together), applies it to the version currently in your `.nimble`
file, writes a new `CHANGELOG.md` section grouped by commit type (with any
breaking changes called out first), and deletes the consumed change files.
If nothing pending would actually change the version (e.g. only `chore`/`docs`
commits since the last release), it exits without touching anything.

## Configuration

`.nimantic-versioning/config.ini` maps each Conventional Commit type to a
bump level. `none` means the type is valid and still shows up in the
changelog, but doesn't bump the version by itself. `ignore` means the type
is valid but is skipped entirely — no change file is recorded and it never
appears in the changelog. This is used for the `version` type, which is the
commit type `bump` uses for its own release commits (unless `--no-commit`
is passed), so running `bump` doesn't cause the release commit itself to
show up as a pending change the next time you run `bump`.

```ini
[types]
feat = minor
fix = patch
perf = patch
refactor = patch
revert = patch
docs = none
style = none
chore = none
test = none
build = none
ci = none
version = ignore
```

Any commit type not listed here is rejected by the `commit-msg` hook. Add
your own types (and adjust bump levels) as needed.

## Testing

```sh
nimble test
```

This builds the binary, then runs `tests/test_e2e.nim`, an end-to-end suite
that drives real `git` + `nimantic_versioning` invocations against throwaway
repos created under `testRepo/` (gitignored). Each test starts from a fresh
repo, so it's always safe to delete `testRepo/` between runs.

## CLI reference

```
nimantic_versioning init
nimantic_versioning install-hooks [--force]
nimantic_versioning bump [--no-commit] [--no-tag] [--dry-run]
nimantic_versioning version

Invoked by installed hooks (not usually run by hand):
  nimantic_versioning check-commit-msg <path-to-message-file>
  nimantic_versioning record-commit
```

## Why two hooks?

A commit's tree is already fixed by the time `commit-msg` runs, so a file
written and staged there does not end up in the commit being created — it
would only surface in whatever commit comes next. To keep each commit
self-contained, `commit-msg` is used purely for validation (and can reject
the commit), while `post-commit` writes the actual bump-note file for the
commit that was just made and folds it in via a guarded `git commit --amend`.

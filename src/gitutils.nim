## Small wrappers around the `git` CLI. We shell out rather than link a Git
## library to keep the tool dependency-free.

import std/[osproc, strutils, sequtils, os]

proc runGit(args: seq[string]): string =
  let (output, code) = execCmdEx("git " & args.map(quoteShell).join(" "))
  if code != 0:
    raise newException(IOError, "git " & args.join(" ") & " failed: " & output.strip())
  output

proc findRepoRoot*(): string =
  ## Locates the root of the current Git working tree.
  runGit(@["rev-parse", "--show-toplevel"]).strip()

proc gitAdd*(repoRoot: string, path: string) =
  discard runGit(@["-C", repoRoot, "add", "-A", "--", path])

proc gitCommit*(repoRoot: string, message: string) =
  discard runGit(@["-C", repoRoot, "commit", "-m", message])

proc gitTag*(repoRoot: string, tag: string) =
  discard runGit(@["-C", repoRoot, "tag", tag])

proc gitLastCommitMessage*(repoRoot: string): string =
  ## Full message (subject + body + footers) of the current HEAD commit.
  runGit(@["-C", repoRoot, "log", "-1", "--pretty=%B"])

proc gitHeadChangedPaths*(repoRoot: string): seq[string] =
  ## Repo-relative paths added/modified/deleted by HEAD, relative to its
  ## parent (or, for a root commit, relative to the empty tree). Used to
  ## check whether HEAD's own diff already contains a change-note file,
  ## which happens whenever this `post-commit` event is amending a commit
  ## that was already recorded rather than a brand-new commit.
  let output = runGit(
    @[
      "-C", repoRoot, "diff-tree", "--no-commit-id", "--name-only", "-r", "--root",
      "HEAD",
    ]
  )
  for line in output.splitLines():
    let l = line.strip()
    if l.len > 0:
      result.add(l)

proc gitAmendNoVerify*(repoRoot: string) =
  ## Folds currently staged changes into HEAD without re-running hooks other
  ## than `post-commit` (which the caller is responsible for guarding against
  ## re-entrancy, e.g. via an environment variable).
  discard runGit(@["-C", repoRoot, "commit", "--amend", "--no-edit", "--no-verify"])

proc isRebaseInProgress*(repoRoot: string): bool =
  ## During `git rebase -i`, each `reword`ed (or otherwise replayed) commit
  ## re-triggers `post-commit`. Amending in response confuses the rebase
  ## sequencer's own bookkeeping (it does its own internal amend for
  ## `reword`, and does not expect us to move HEAD again on top of that), so
  ## the caller should treat this as a no-op while a rebase is in progress.
  dirExists(repoRoot / ".git" / "rebase-merge") or
    dirExists(repoRoot / ".git" / "rebase-apply")

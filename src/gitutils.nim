## Small wrappers around the `git` CLI. We shell out rather than link a Git
## library to keep the tool dependency-free.

import std/[osproc, strutils, sequtils]

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

proc gitParentHash*(repoRoot: string): string =
  ## Hash of HEAD's parent commit, or "" if HEAD is the repository's root
  ## commit. Unlike a commit's own hash, this stays the same across any
  ## number of `commit --amend`s, so it can be used to recognize "this is
  ## still the same logical commit, just amended" across post-commit events.
  try:
    runGit(@["-C", repoRoot, "rev-parse", "HEAD^"]).strip()
  except IOError:
    ""

proc gitAmendNoVerify*(repoRoot: string) =
  ## Folds currently staged changes into HEAD without re-running hooks other
  ## than `post-commit` (which the caller is responsible for guarding against
  ## re-entrancy, e.g. via an environment variable).
  discard runGit(@["-C", repoRoot, "commit", "--amend", "--no-edit", "--no-verify"])

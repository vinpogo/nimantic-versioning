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

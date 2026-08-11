## Installs the `commit-msg` Git hook that delegates to this binary.

import std/os

const CommitMsgHook = """#!/bin/sh
# Installed by nimantic-versioning. Do not edit by hand;
# re-run `nimantic_versioning install-hooks --force` to regenerate.
exec nimantic_versioning check-commit-msg "$1"
"""

proc installHooks*(repoRoot: string, force: bool) =
  let hooksDir = repoRoot / ".git" / "hooks"
  if not dirExists(hooksDir):
    raise newException(IOError, "No .git/hooks directory found at " & hooksDir)

  let hookPath = hooksDir / "commit-msg"
  if fileExists(hookPath) and not force:
    raise newException(
      IOError,
      "Hook already exists at " & hookPath & ". Re-run with --force to overwrite.",
    )

  writeFile(hookPath, CommitMsgHook)
  setFilePermissions(
    hookPath,
    {
      fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec, fpOthersRead,
      fpOthersExec,
    },
  )

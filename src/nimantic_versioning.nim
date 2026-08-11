## nimantic-versioning: semantic versioning for Nim projects, driven by
## Conventional Commits and wired into Git via a `commit-msg` hook.

import std/[os, strutils, sequtils, algorithm, tables]
import ./gitutils
import ./config
import ./commitparser
import ./changes
import ./nimblefile
import ./changelog
import ./hooks
import ./semver

const Usage = """
nimantic-versioning - semantic versioning from Conventional Commits

Usage:
  nimantic_versioning init
  nimantic_versioning install-hooks [--force]
  nimantic_versioning bump [--commit] [--tag] [--dry-run]

Invoked by installed hooks (not usually run by hand):
  nimantic_versioning check-commit-msg <path-to-message-file>
  nimantic_versioning record-commit
"""

proc cmdInit(repoRoot: string) =
  createDir(changesDir(repoRoot))
  let cfgPath = configPath(repoRoot)
  if fileExists(cfgPath):
    echo "Config already exists at ", cfgPath
  else:
    writeFile(cfgPath, DefaultConfig)
    echo "Created ", cfgPath
  echo "Run `nimantic_versioning install-hooks` to wire up the commit-msg hook."

proc cmdInstallHooks(repoRoot: string, force: bool) =
  installHooks(repoRoot, force)
  let hooksDir = repoRoot / ".git" / "hooks"
  echo "Installed commit-msg hook at ", hooksDir / "commit-msg"
  echo "Installed post-commit hook at ", hooksDir / "post-commit"

proc validateAndLookup(cfg: Config, parsed: ParsedCommit): (bool, string, BumpLevel) =
  ## Returns `(ok, errorMessage, bumpLevel)`.
  let (known, configuredLevel) = lookupType(cfg, parsed.commitType)
  if not known:
    let allowed = toSeq(cfg.types.keys).sorted().join(", ")
    return (
      false,
      "unknown commit type '" & parsed.commitType & "'. Allowed types: " & allowed,
      blNone,
    )
  let bumpLevel = if parsed.breaking: blMajor else: configuredLevel
  (true, "", bumpLevel)

proc cmdCheckCommitMsg(repoRoot: string, msgFilePath: string) =
  ## Runs as the `commit-msg` hook. Only validates; the commit's tree is
  ## already fixed by this point, so writing the bump-note file here would
  ## not end up in the commit being created (see `record-commit`).
  let raw = readFile(msgFilePath)
  let (ok, err, parsed) = parseCommitMessage(raw)
  if not ok:
    stderr.writeLine("nimantic-versioning: invalid commit message: " & err)
    quit(1)

  let cfg = loadConfig(repoRoot)
  let (validType, typeErr, _) = validateAndLookup(cfg, parsed)
  if not validType:
    stderr.writeLine("nimantic-versioning: " & typeErr)
    quit(1)

proc cmdRecordCommit(repoRoot: string) =
  ## Runs as the `post-commit` hook. Writes the bump-note file for the
  ## commit that was just created and folds it into that same commit via a
  ## guarded amend (see the `post-commit` hook script for the re-entrancy
  ## guard).
  let raw = gitLastCommitMessage(repoRoot)
  let (ok, err, parsed) = parseCommitMessage(raw)
  if not ok:
    stderr.writeLine("nimantic-versioning: skipping unparseable commit: " & err)
    return

  let cfg = loadConfig(repoRoot)
  let (validType, typeErr, bumpLevel) = validateAndLookup(cfg, parsed)
  if not validType:
    stderr.writeLine("nimantic-versioning: skipping commit: " & typeErr)
    return

  if bumpLevel == blIgnore:
    # e.g. `version: ...` commits made by `bump --commit` itself, or other
    # types explicitly configured as "ignore" - no change file, no amend.
    return

  let path = writeChangeFile(
    repoRoot, parsed.commitType, bumpLevel, parsed.breaking, parsed.rawMessage
  )
  gitAdd(repoRoot, path)
  putEnv("NIMANTIC_VERSIONING_AMENDING", "1")
  gitAmendNoVerify(repoRoot)

proc cmdBump(repoRoot: string, doCommit, doTag, dryRun: bool) =
  let entries = readChangeFiles(repoRoot)
  if entries.len == 0:
    echo "No pending changes found in .nimantic-versioning/changes. Nothing to bump."
    return

  var overall = blNone
  for e in entries:
    if e.bumpLevel > overall:
      overall = e.bumpLevel

  if overall == blNone:
    echo "All pending changes are non-version-impacting (bump=none). Nothing to bump."
    return

  let nimblePath = findNimbleFile(repoRoot)
  let current = readVersion(nimblePath)
  let next = bump(current, overall)
  let section = buildSection(next, entries)
  let changelogPath = repoRoot / "CHANGELOG.md"

  echo "Bumping version: ", $current, " -> ", $next, " (", $overall, ")"
  if dryRun:
    echo "\n--- CHANGELOG entry (dry run, nothing written) ---"
    echo section
    return

  writeVersion(nimblePath, next)
  prependToChangelog(changelogPath, section)
  deleteChangeFiles(entries)
  echo "Updated ", nimblePath
  echo "Updated ", changelogPath

  if doCommit:
    gitAdd(repoRoot, nimblePath)
    gitAdd(repoRoot, changelogPath)
    gitAdd(repoRoot, changesDir(repoRoot))
    gitCommit(repoRoot, "version: v" & $next)
    echo "Created release commit."

  if doTag:
    gitTag(repoRoot, "v" & $next)
    echo "Created tag v" & $next

when isMainModule:
  let args = commandLineParams()
  if args.len == 0:
    echo Usage
    quit(1)

  var repoRoot: string
  try:
    repoRoot = findRepoRoot()
  except IOError as e:
    stderr.writeLine("nimantic-versioning: " & e.msg)
    quit(1)

  try:
    case args[0]
    of "init":
      cmdInit(repoRoot)
    of "install-hooks":
      cmdInstallHooks(repoRoot, "--force" in args)
    of "check-commit-msg":
      if args.len < 2:
        stderr.writeLine(
          "Usage: nimantic_versioning check-commit-msg <path-to-message-file>"
        )
        quit(1)
      cmdCheckCommitMsg(repoRoot, args[1])
    of "record-commit":
      cmdRecordCommit(repoRoot)
    of "bump":
      cmdBump(repoRoot, "--commit" in args, "--tag" in args, "--dry-run" in args)
    else:
      echo Usage
      quit(1)
  except IOError as e:
    stderr.writeLine("nimantic-versioning: " & e.msg)
    quit(1)

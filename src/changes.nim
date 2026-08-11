## Reads and writes the per-commit "pending version bump" files stored under
## `.nimantic-versioning/changes/`.

import std/[os, strutils, times, random, sequtils, algorithm]
import ./semver

type ChangeEntry* = object
  commitType*: string
  bumpLevel*: BumpLevel
  breaking*: bool
  message*: string
  path*: string
  parentHash*: string
    ## Hash of the commit's parent at the time this note
    ## was written. Stable across `commit --amend`, so it identifies "the
    ## same logical commit" even after its own hash changes.

proc changesDir*(repoRoot: string): string =
  repoRoot / ".nimantic-versioning" / "changes"

proc randomSlug(): string =
  ## A timestamp prefix keeps files sorted chronologically; the random
  ## suffix avoids collisions between commits made in the same millisecond.
  let millis = int64(epochTime() * 1000)
  let suffix = toHex(rand(0 .. 0xFFFFFF), 6).toLowerAscii()
  $millis & "-" & suffix

proc writeChangeFile*(
    repoRoot, commitType: string,
    bumpLevel: BumpLevel,
    breaking: bool,
    message: string,
    parentHash: string = "",
): string =
  randomize()
  let dir = changesDir(repoRoot)
  createDir(dir)
  let path = dir / (randomSlug() & ".txt")
  let content =
    "type=" & commitType & "\n" & "bump=" & $bumpLevel & "\n" & "breaking=" &
    (if breaking: "true" else: "false") & "\n" & "parent=" & parentHash & "\n" & "===\n" &
    message & "\n"
  writeFile(path, content)
  path

proc parseChangeFile(path: string): ChangeEntry =
  let content = readFile(path)
  const separator = "===\n"
  let sepIdx = content.find(separator)
  if sepIdx == -1:
    raise
      newException(IOError, "Malformed change file (missing '===' separator): " & path)

  let header = content[0 ..< sepIdx]
  let message =
    content[sepIdx + separator.len .. ^1].strip(leading = false, trailing = true)

  var commitType = ""
  var bumpLevel = blNone
  var breaking = false
  var parentHash = ""
  for line in header.splitLines():
    if line.len == 0:
      continue
    let kv = line.split('=', 1)
    if kv.len != 2:
      continue
    case kv[0]
    of "type":
      commitType = kv[1]
    of "bump":
      bumpLevel = parseBumpLevel(kv[1])
    of "breaking":
      breaking = kv[1] == "true"
    of "parent":
      parentHash = kv[1]
    else:
      discard

  ChangeEntry(
    commitType: commitType,
    bumpLevel: bumpLevel,
    breaking: breaking,
    message: message,
    path: path,
    parentHash: parentHash,
  )

proc readChangeFiles*(repoRoot: string): seq[ChangeEntry] =
  let dir = changesDir(repoRoot)
  if not dirExists(dir):
    return @[]
  var files: seq[string] = @[]
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".txt"):
      files.add(path)
  files.sort() # filenames are timestamp-prefixed, so this is chronological order.
  files.mapIt(parseChangeFile(it))

proc deleteChangeFiles*(entries: seq[ChangeEntry]) =
  for entry in entries:
    removeFile(entry.path)

proc findChangeFileForParent*(repoRoot: string, parentHash: string): string =
  ## Returns the path of a pending change file already recorded for a commit
  ## at the same position in history (same parent), or "" if none exists.
  ## Used to recognize that a `post-commit` event is amending a commit that
  ## already has a note, rather than being a brand-new commit.
  if parentHash.len == 0:
    return ""
  for entry in readChangeFiles(repoRoot):
    if entry.parentHash == parentHash:
      return entry.path
  ""

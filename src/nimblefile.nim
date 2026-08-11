## Reads and rewrites the `version` field of the project's `.nimble` file.

import std/[os, strutils]
import ./semver

proc findNimbleFile*(repoRoot: string): string =
  for kind, path in walkDir(repoRoot):
    if kind == pcFile and path.endsWith(".nimble"):
      return path
  raise newException(IOError, "No .nimble file found in " & repoRoot)

proc isVersionLine(line: string): bool =
  let stripped = line.strip()
  stripped.startsWith("version") and stripped.find('=') != -1

proc readVersion*(nimblePath: string): SemVer =
  for line in lines(nimblePath):
    if isVersionLine(line):
      let eqIdx = line.find('=')
      let value = line[eqIdx + 1 .. ^1].strip().strip(chars = {'"', '\''})
      return parseSemVer(value)
  raise newException(IOError, "Could not find a 'version' field in " & nimblePath)

proc writeVersion*(nimblePath: string, newVersion: SemVer) =
  var outLines: seq[string] = @[]
  var replaced = false
  for line in lines(nimblePath):
    if not replaced and isVersionLine(line):
      let eqIdx = line.find('=')
      outLines.add(line[0 .. eqIdx] & " \"" & $newVersion & "\"")
      replaced = true
    else:
      outLines.add(line)
  if not replaced:
    raise newException(
      IOError, "Could not find a 'version' field to update in " & nimblePath
    )
  writeFile(nimblePath, outLines.join("\n") & "\n")

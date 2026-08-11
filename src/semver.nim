## Minimal semantic version (major.minor.patch) parsing and bumping.

import std/strutils

type
  BumpLevel* = enum
    blNone
    blPatch
    blMinor
    blMajor

  SemVer* = object
    major*, minor*, patch*: int

proc `$`*(v: SemVer): string =
  $v.major & "." & $v.minor & "." & $v.patch

proc parseSemVer*(s: string): SemVer =
  ## Parses the `major.minor.patch` core of a version string, ignoring any
  ## pre-release (`-...`) or build metadata (`+...`) suffix.
  let core = s.strip().split('+', 1)[0].split('-', 1)[0]
  let parts = core.split('.')
  if parts.len != 3:
    raise newException(ValueError, "Invalid semantic version: " & s)
  result = SemVer(
    major: parseInt(parts[0]), minor: parseInt(parts[1]), patch: parseInt(parts[2])
  )

proc bump*(v: SemVer, level: BumpLevel): SemVer =
  case level
  of blMajor:
    SemVer(major: v.major + 1, minor: 0, patch: 0)
  of blMinor:
    SemVer(major: v.major, minor: v.minor + 1, patch: 0)
  of blPatch:
    SemVer(major: v.major, minor: v.minor, patch: v.patch + 1)
  of blNone:
    v

proc `$`*(level: BumpLevel): string =
  case level
  of blMajor: "major"
  of blMinor: "minor"
  of blPatch: "patch"
  of blNone: "none"

proc parseBumpLevel*(s: string): BumpLevel =
  case s.strip().toLowerAscii()
  of "major":
    blMajor
  of "minor":
    blMinor
  of "patch":
    blPatch
  of "none":
    blNone
  else:
    raise newException(ValueError, "Invalid bump level: " & s)

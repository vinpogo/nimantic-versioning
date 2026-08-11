## Parses and validates a Conventional Commits (https://www.conventionalcommits.org)
## header of the form `type(scope)!: subject`, without relying on regex/PCRE.

import std/strutils

type ParsedCommit* = object
  commitType*: string
  scope*: string
  breaking*: bool
  subject*: string
  rawMessage*: string ## Full message, comments and trailing blank lines removed.

proc stripCommentsAndTrailingBlank(raw: string): string =
  var lines: seq[string] = @[]
  for line in raw.splitLines():
    if line.startsWith("#"):
      continue
    lines.add(line)
  while lines.len > 0 and lines[^1].strip().len == 0:
    discard lines.pop()
  lines.join("\n")

proc hasBreakingFooter(message: string): bool =
  for line in message.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("BREAKING CHANGE:") or trimmed.startsWith("BREAKING-CHANGE:"):
      return true
  false

proc isValidTypeToken(s: string): bool =
  if s.len == 0:
    return false
  for c in s:
    if not (c.isAlphaAscii() or c == '-'):
      return false
  true

proc parseCommitMessage*(raw: string): (bool, string, ParsedCommit) =
  ## Returns `(ok, errorMessage, parsedCommit)`.
  let cleaned = stripCommentsAndTrailingBlank(raw)
  if cleaned.strip().len == 0:
    return (false, "Commit message is empty.", ParsedCommit())

  let headerLine = cleaned.splitLines()[0]
  let sepIdx = headerLine.find(": ")
  if sepIdx == -1:
    return (
      false,
      "Header must match 'type(scope)!: subject' (missing a ': ' separator).",
      ParsedCommit(),
    )

  var prefix = headerLine[0 ..< sepIdx]
  let subject = headerLine[sepIdx + 2 .. ^1].strip()
  if subject.len == 0:
    return (false, "Commit subject must not be empty.", ParsedCommit())

  var breaking = false
  if prefix.endsWith("!"):
    breaking = true
    prefix = prefix[0 ..< prefix.high]

  var commitType = prefix
  var scope = ""
  let parenStart = prefix.find('(')
  if parenStart != -1:
    if not prefix.endsWith(")"):
      return (false, "Unbalanced parentheses in commit scope.", ParsedCommit())
    commitType = prefix[0 ..< parenStart]
    scope = prefix[parenStart + 1 ..< prefix.high]

  if not isValidTypeToken(commitType):
    return (
      false,
      "Commit type must be alphabetic (e.g. 'feat', 'fix'), got: '" & commitType & "'.",
      ParsedCommit(),
    )

  if hasBreakingFooter(cleaned):
    breaking = true

  let parsed = ParsedCommit(
    commitType: commitType.toLowerAscii(),
    scope: scope,
    breaking: breaking,
    subject: subject,
    rawMessage: cleaned,
  )
  (true, "", parsed)

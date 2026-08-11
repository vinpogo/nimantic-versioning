## End-to-end tests. Each test spins up a throwaway Git repo under
## `testRepo/` (gitignored, safe to blow away) and drives it through real
## `git` + `nimantic_versioning` invocations, exactly as a user would.
##
## Run via `nimble test` (builds the binary first, then runs this file).

import std/[unittest, os, osproc, strutils, strtabs, sequtils]

const ProjectRoot = currentSourcePath().parentDir().parentDir()
const TestRepoRoot = ProjectRoot / "testRepo"

proc testEnv(): StringTableRef =
  ## The freshly built binary lives at the project root; prepend it to PATH
  ## so the installed Git hooks (`exec nimantic_versioning ...`) resolve to
  ## it instead of whatever else might be installed on the system.
  result = newStringTable(modeCaseSensitive)
  for k, v in envPairs():
    result[k] = v
  result["PATH"] = ProjectRoot & ":" & result.getOrDefault("PATH", "")

proc run(cmd: string, dir: string): tuple[output: string, code: int] =
  let r = execCmdEx(cmd, workingDir = dir, env = testEnv())
  (r.output, r.exitCode)

proc changeNotes(dir: string): seq[string] =
  toSeq(walkFiles(dir / ".nimantic-versioning" / "changes" / "*.txt"))

proc freshRepo(name: string): string =
  ## A repo with one commit and an initial `pkg.nimble` at 0.1.0, with
  ## nimantic-versioning initialized and its hooks installed.
  result = TestRepoRoot / name
  removeDir(result)
  createDir(result)

  var r = run("git init -q", result)
  doAssert r.code == 0, "git init failed: " & r.output
  discard run("git config user.email test@example.com", result)
  discard run("git config user.name Test", result)

  writeFile(result / "pkg.nimble", "version = \"0.1.0\"\n")
  discard run("git add -A", result)
  r = run("git commit -q -m \"chore: init\"", result)
  doAssert r.code == 0, "initial commit failed: " & r.output

  r = run("nimantic_versioning init", result)
  doAssert r.code == 0, "init failed: " & r.output
  r = run("nimantic_versioning install-hooks", result)
  doAssert r.code == 0, "install-hooks failed: " & r.output

proc commitFile(
    dir, fileName, contents, message: string
): tuple[output: string, code: int] =
  writeFile(dir / fileName, contents)
  discard run("git add -A", dir)
  run("git commit -q -m \"" & message & "\"", dir)

removeDir(TestRepoRoot)
createDir(TestRepoRoot)

suite "end-to-end":
  test "valid commit records a change note":
    let dir = freshRepo("valid-commit")
    let (output, code) = commitFile(dir, "a.txt", "hi", "feat: add a")
    check code == 0
    let notes = changeNotes(dir)
    check notes.len == 1
    let content = readFile(notes[0])
    check "type=feat" in content
    check "bump=minor" in content
    check "breaking=false" in content
    check "feat: add a" in content
    discard output

  test "invalid commit type is rejected by the commit-msg hook":
    let dir = freshRepo("invalid-type")
    let (_, code) = commitFile(dir, "a.txt", "hi", "bogus: nope")
    check code != 0
    check changeNotes(dir).len == 0

  test "breaking change forces a major bump regardless of type mapping":
    let dir = freshRepo("breaking")
    let (_, code) = commitFile(dir, "a.txt", "hi", "fix!: breaking fix")
    check code == 0
    let notes = changeNotes(dir)
    check notes.len == 1
    check "breaking=true" in readFile(notes[0])
    let (out1, _) = run("nimantic_versioning bump --dry-run", dir)
    check "-> 1.0.0 (major)" in out1

  test "amending a commit replaces its note instead of duplicating":
    let dir = freshRepo("amend-dedupe")
    var r = commitFile(dir, "a.txt", "hi", "feat: first")
    check r.code == 0
    check changeNotes(dir).len == 1

    r = run("git commit --amend -q -m \"feat: second\"", dir)
    check r.code == 0
    var notes = changeNotes(dir)
    check notes.len == 1
    check "feat: second" in readFile(notes[0])

    r = run("git commit --amend -q -m \"version: v9.9.9\"", dir)
    check r.code == 0
    check changeNotes(dir).len == 0

    let status = run("git status --porcelain", dir)
    check status.output.strip().len == 0

  test "bump updates the .nimble version and changelog, then clears notes":
    let dir = freshRepo("bump-basic")
    discard commitFile(dir, "a.txt", "hi", "feat: add feature")
    let (output, code) = run("nimantic_versioning bump", dir)
    check code == 0
    check "0.1.0 -> 0.2.0" in output
    check "0.2.0" in readFile(dir / "pkg.nimble")
    check fileExists(dir / "CHANGELOG.md")
    check changeNotes(dir).len == 0

  test "bump with no pending changes is a no-op":
    let dir = freshRepo("bump-empty")
    let (output, code) = run("nimantic_versioning bump", dir)
    check code == 0
    check "Nothing to bump" in output
    check "0.1.0" in readFile(dir / "pkg.nimble")

  test "bump --commit's release commit is not recorded as a pending change":
    let dir = freshRepo("bump-commit")
    discard commitFile(dir, "a.txt", "hi", "feat: add feature")
    let (_, code) = run("nimantic_versioning bump --commit", dir)
    check code == 0
    let (subject, _) = run("git log -1 --pretty=%s", dir)
    check subject.strip() == "version: v0.2.0"
    check changeNotes(dir).len == 0

  test "bump --tag creates a matching tag":
    let dir = freshRepo("bump-tag")
    discard commitFile(dir, "a.txt", "hi", "fix: patch it")
    let (_, code) = run("nimantic_versioning bump --commit --tag", dir)
    check code == 0
    let (tags, _) = run("git tag", dir)
    check "v0.1.1" in tags

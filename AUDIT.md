# Audit log

Last full audit: **22 Sep 2026** — the day the package was extracted from Sidewatch's app target. Every file
had been logic-reviewed there on 18–21 Sep 2026 and shipped behind mutation-verified harness cases, which
are now this package's tests. Add a dated line under *History* when you audit again, and keep *Known
non-issues* current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the package or the family.
   Public API is NOT dead because Sidewatch does not call it.
3. Risky patterns: `Timer` without `invalidate`, `addObserver(forName:)` without `removeObserver`, `as!`, `try!`
   outside literal regexes, `fatalError` outside `init?(coder:)`, `print(` outside tests, TODO/FIXME left behind.
4. Docs drift: every name in CLAUDE.md's module map exists; AGENTS.md mirrors CLAUDE.md; README Usage matches the API.

## Result on 22 Sep 2026

- Build: clean under tools 6.2 and Swift 6 language mode. Tests: 28 green (four suites: SQL, schema, dependencies, surface).
- The public surface was made deliberately: the readers' static functions and the fact types with memberwise
  inits; the regex and text helpers are public because Sidewatch's diff renderers and the Timeline's command
  classifier reach them.

## Known non-issues

- The regex patterns are compiled with `try?` and matched per call; the texts are single files, not corpora.

## History

- 22 Sep 2026 — extracted from Sidewatch; first family audit.
- 22 Sep 2026 (later) — `DatabaseCommands`, `TestRuns` and `ShellCommandLine` moved in from Sidewatch's `AgentDatabaseCommands` / `AgentTestRuns` (the transcript walk stays in the app); `parse` split into one reader per runner family; the regex helper is `Support/RegexMatches` with `DependencyChanges.matches` forwarding. Fixed while porting: golang-migrate's verb was read as the value of `-path` (`migrate -path db -database $URL down -all` was not a command at all) — pinned by `DatabaseCommandsTests`.

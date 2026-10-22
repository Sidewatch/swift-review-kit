# Swift Review Kit

What a change did, for the person reviewing it: line-pinned review notes, facts a change establishes (destructive SQL, dependencies, tests), and the callers and tests a touched symbol reaches.

- Modules `ReviewKit`, `ChangeFacts`, `BlastRadius`, each in `Sources/<Module>` with tests in `Tests/<Module>Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.
- Each module's user-facing documentation is `Docs/Modules/<Module>.md`; its last audit is `Docs/Audits/<Module>.md` — read it before auditing, and extend it rather than redo it.

## ReviewKit — `Sources/ReviewKit`

### Module map
- `Core/` — the engine: ReviewDraft, ReviewSession (reviewed marks with content stamps, per repo), TurnCheckpointStore, TurnAttribution (each line's turn from the turns' snapshots; another session's turn named only while it kept taking turns), DiffLineLocator (`locate` one rendered line, `locateAll` every line in one pass: the numbers a diff view shows)
- `Enums/` — enums with no behaviour beyond their cases and labels: ReviewSeverity
- `Models/` — value types — the shape of a thing, nothing else: ReviewComment, DiffReviewComment, TurnCheckpoint, ReviewMark
- `Support/` — pure helpers: RepoKey, DiffReviewMessage, ReviewMarkRecords (the stored shape of the marks, both ways), LineOrigins (each line's first version over any sequence of texts; stdlib `difference(from:)`, matched by content past `diffBudget` because a rewrite is quadratic)

## ChangeFacts — `Sources/ChangeFacts`

### Module map
- `SQL/` — `DestructiveSQL`: `findings(in:path:addedLines:)` (DROP, TRUNCATE, an unconditioned DELETE or UPDATE, a column type change; comments and literals per dialect; a dump is one finding; tests and vendored trees skipped), `marks(forChunk:path:)` for a diff, `tooltip(for:)`
- `Schema/` — `SchemaDDL` (Prisma / Rails / Django → CREATE TABLE DDL), `SchemaModel` (tables, columns, keys, indexes, from any DDL through a tolerant build), `SchemaDiff` (`compare`, `facts(oldText:newText:path:)`, `headline`, `tooltip`)
- `Dependencies/` — `DependencyManifest` (which files are manifests, by name), `DependencyChanges` (`declarations(in:path:)` per format, `facts(oldText:newText:path:)`, `headline`, `isLockfile`)
- `Surface/` — `AddedLineSurface` (`scan`, `findings(oldText:newText:path:addedLines:)`, `tooltip`: environment names read and hosts called on added lines, minus what the old text already used)
- `Commands/` — `DatabaseCommands` (`detect(_:timestamp:)`: every database command in a shell line, `Command` with tool, severity, summary), `TestRuns` (`runs(in:output:isError:timestamp:)`, `runner(of:)`, `parse(runner:output:isError:)` one private reader per runner family, `isTestPath`, `testFilesTally`)
- `Support/` — `ShellCommandLine` (`segments(of:)`, `words(_:)`, `invocation(of:)` — the shell reading both command readers share), `RegexMatches` (every match as its groups; `DependencyChanges.matches` forwards to it)

Sidewatch keeps the git-backed halves — the old side from HEAD, the added lines from `git diff`, the
memoised badge notes — and the transcript-backed halves (`commands(in:turn:)`, `runs(in:turn:)` over
its timeline) as extensions in its own target.

## BlastRadius — `Sources/BlastRadius`

### Module map
- `Core/` — the engine: BlastRadius
- `Models/` — value types — the shape of a thing, nothing else: BlastLocation, SymbolImpact

## Rules

Read `CONTRIBUTING.md` for the folder layout and the pull-request rules.

@CONTRIBUTING.md

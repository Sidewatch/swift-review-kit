# Swift Change Facts

What a change to a codebase DID, as facts a reviewer can hold against a brief — never a judgement.
The statements a change adds that can lose data (SQL and the migration DSLs agents write), a schema
read as structure from SQL, Prisma, Rails `schema.rb` or Django `models.py` and the diff of two of
them, a dependency manifest's declarations in fourteen formats and what changed by name, and the
environment names and hosts a change starts reading and calling; and the shell lines an agent ran —
the database commands among them with the severity the SQL or the subcommand earns, and the test
runs with what each reported. Every reader takes texts and returns facts; nothing here touches git,
a transcript or a network.

- Module `ChangeFacts` in `Sources/ChangeFacts`; tests in `Tests` (fixtures under `Tests/ChangeFactsTests/Fixtures`); `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+. One dependency, swift-sqlite-reader (a schema is built by running its DDL into an in-memory SQLite, one statement at a time) — the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `SQL/` — `DestructiveSQL`: `findings(in:path:addedLines:)` (DROP, TRUNCATE, an unconditioned DELETE or UPDATE, a column type change; comments and literals per dialect; a dump is one finding; tests and vendored trees skipped), `marks(forChunk:path:)` for a diff, `tooltip(for:)`
- `Schema/` — `SchemaDDL` (Prisma / Rails / Django → CREATE TABLE DDL), `SchemaModel` (tables, columns, keys, indexes, from any DDL through a tolerant build), `SchemaDiff` (`compare`, `facts(oldText:newText:path:)`, `headline`, `tooltip`)
- `Dependencies/` — `DependencyManifest` (which files are manifests, by name), `DependencyChanges` (`declarations(in:path:)` per format, `facts(oldText:newText:path:)`, `headline`, `isLockfile`)
- `Surface/` — `AddedLineSurface` (`scan`, `findings(oldText:newText:path:addedLines:)`, `tooltip`: environment names read and hosts called on added lines, minus what the old text already used)
- `Commands/` — `DatabaseCommands` (`detect(_:timestamp:)`: every database command in a shell line, `Command` with tool, severity, summary), `TestRuns` (`runs(in:output:isError:timestamp:)`, `runner(of:)`, `parse(runner:output:isError:)` one private reader per runner family, `isTestPath`, `testFilesTally`)
- `Support/` — `ShellCommandLine` (`segments(of:)`, `words(_:)`, `invocation(of:)` — the shell reading both command readers share), `RegexMatches` (every match as its groups; `DependencyChanges.matches` forwards to it)

Sidewatch keeps the git-backed halves — the old side from HEAD, the added lines from `git diff`, the
memoised badge notes — and the transcript-backed halves (`commands(in:turn:)`, `runs(in:turn:)` over
its timeline) as extensions in its own target.

## Rules

Read `CONTRIBUTING.md` before changing anything: it is the layout and PR rulebook for this package.

- **Auditing? Read `AUDIT.md` first** — what the last full audit checked and fixed, and the known non-issues to skip; extend it, do not redo it.

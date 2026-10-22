# Audit log

Last full audit: **17 Sep 2026** — every source file covered by the MECHANICAL checks below (build warnings, tests,
dead-code and risk-pattern scans, docs drift); line-by-line logic review was targeted at the areas changed since
5 Sep 2026, not the whole tree. Nothing needs re-scanning unless it changed after that date. Add a dated line under *History* when you audit again, and keep the
*Known non-issues* list current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the app or the family
   (`grep -w` across `*.swift` AND non-Swift files — selectors and MCP names live in strings). Protocol
   requirements, `override`s, `@objc` actions and public API are NOT dead because Sidewatch does not call them.
3. Risky patterns: `Timer` without `invalidate`, `addObserver(forName:)` without `removeObserver`, `as!`, `try!`
   outside literal regexes, `fatalError` outside `init?(coder:)`, `print(` outside harnesses, TODO/FIXME left behind.
4. Docs drift: every name in CLAUDE.md's module map exists; AGENTS.md mirrors CLAUDE.md; README Usage matches the API.

## Result on 17 Sep 2026

- Build: clean. Tests: green.
- Nothing to fix in this package.

## Logic review — 18 Sep 2026 (every source and test file, line by line)

Nothing to fix. Checked: `ReviewSession`'s save/load round trip, `ReviewDraft`,
`TurnCheckpointStore.record`'s pruning and its returned paths, `DiffLineLocator`'s hunk replay (a
removed line maps to its OLD number), `DiffReviewMessage.format`, `PRReviewExporter`.

## Reviewed marks — 9 Oct 2026

Fixed, each pinned by a test that fails against the old code (`ReviewSessionStampTests`, over a
throwaway `UserDefaults` suite through the new `ReviewSession(defaults:)` initializer):

- **A file the agent edited again stayed "reviewed".** Marks were keyed by path alone. A mark now
  carries an optional content stamp (`ReviewMark`), the working-tree blob hash the host computes:
  `markReviewed(_:stamp:)`, `isReviewed(_:stamp:)`, `toggle(_:stamp:)`,
  `reviewedCount(in:stamp:)`. A stored stamp matches only the same stamp; a mark without one
  matches only a nil question; the unstamped API is the stamped one with a nil stamp. Pinned by
  `testAMarkAnswersOnlyForTheStampItWasMadeWith`,
  `testReMarkingWithANewStampReplacesTheOldOneAndFiresOnlyOnAChange`,
  `testToggleWithAStampMarksAStaleFileRatherThanClearingIt`, `testReviewedCountTakesEachPathsStamp`.
  Mutant: `isReviewed(_:stamp:)` answering true for any mark on the path — 12 failures.
- **`prune(to: [])` deleted every mark for the repo.** An all-empty status snapshot is a `git
  stash` or a checkout away from the branch, not a review outcome; the marks must be there when
  the changes come back. The empty set is now a no-op; a non-empty set still drops absent paths.
  Pinned by `testPruneToAnEmptySetKeepsEveryMark` and `testPruneToANonEmptySetStillDropsAbsentPaths`.
  Mutant: the empty-set guard removed — 3 failures.
- **Persistence** (`Support/ReviewMarkRecords`): repo key → path → stamp, an empty string for
  no stamp (a property list holds no nil; a blob hash is never empty). The previous repo key →
  [path] list is not migrated, pre-launch; it fails the read and the marks start empty
  (`testTheOldPathListFormatIsNotRead`). Pinned by `testStampsSurviveARelaunch`: a second
  session over the same defaults sees the stamps and the stored dictionary. Mutant: stamps
  written as empty strings — 4 failures. `testSessionEmptyRepoEntriesAreRemovedFromPersistedStore`
  reads the new shape.

## Known non-issues (do not "fix" these again)

- None recorded.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review (every source and test file, line by line), Claude with David.
- 9 Oct 2026 — reviewed marks: content stamps, `prune(to: [])` a no-op, stored shape changed (above).
- 23 Oct 2026 — `LineOrigins` + `TurnAttribution` (18 tests, 10 mutants each failing: inserted lines,
  removed-line skip, the diff budget, content reuse, the unshared count, the line cap, finished and
  earliest sessions, pre-watch lines, the own session beside). A whole-file rewrite measured 1.75 s
  (10k lines) / 6.9 s (20k) per step through the line diff; past the budget it is matched by content.

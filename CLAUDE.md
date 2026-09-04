# Swift Review Kit

A tiny, dependency-free model layer for a code-review pass over a set of changed files — collect line-pinned comments and emit them as one clean markdown block, and track which files you've marked *reviewed* across relaunches. The verify-what-changed core behind Sidewatch's "Send to Agent" surface.

- Module `ReviewKit` in `Sources/ReviewKit`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.0, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: ReviewDraft, ReviewSession, TurnCheckpointStore
- `Enums/` — enums with no behaviour beyond their cases and labels: ReviewSeverity
- `Models/` — value types — the shape of a thing, nothing else: ReviewComment

## Rules

@CONTRIBUTING.md

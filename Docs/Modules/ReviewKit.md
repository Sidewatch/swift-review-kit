# Swift Review Kit

A small model layer for a code-review pass over a set of changed files — collect line-pinned comments and emit them as one clean markdown block, and track which files you've marked *reviewed* across relaunches. The verify-what-changed core behind Sidewatch's "Send to Agent" surface.

## Features

- **Line-pinned comments** — `ReviewComment` carries a `file`, `line`, `severity`, and `note`
- **Severities** — `ReviewSeverity`: `must-fix`, `suggestion`, `question` (the raw value is the markdown label)
- **Markdown emit** — `ReviewDraft.markdown()` groups by file, sorts by line, and indents multi-line notes so they stay inside their bullet
- **Reviewed set** — `ReviewSession.toggle(_:)` / `markReviewed(_:_:)` / `reviewedCount(in:)` to walk a change set to completion (N of M)
- **Content stamps** — `markReviewed(_:stamp:)` / `isReviewed(_:stamp:)` / `toggle(_:stamp:)` / `reviewedCount(in:stamp:)` tie a mark to the content it was made against (the working-tree blob hash you compute): the agent editing the file again changes the stamp and the file is no longer reviewed. The unstamped calls are the stamped ones with a nil stamp, so a stamped mark never answers an unstamped question and an unstamped mark never answers a stamped one
- **Per-repo persistence** — every `ReviewSession` call names its repository (two windows may show two at once); it survives relaunch via `UserDefaults`, stamps included
- **Prune** — `ReviewSession.prune(to:)` drops reviewed entries no longer in the live change set; an empty set is a no-op, since a snapshot with no changes at all is a stash or a checkout away from the branch, not a review outcome
- **Small** — Foundation plus swift-foundation-extensions (FoundationExtensions, ProcessRunner)
- **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- macOS 14+ (Foundation only; other Apple platforms at SwiftPM's default minimums)
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-review-kit.git", from: "0.1.0")
]
```

## Usage

### Composing review feedback

```swift
import ReviewKit

ReviewDraft.shared.add(ReviewComment(file: "App.swift", line: 42,
                                     severity: .mustFix, note: "Force-unwrap can crash here."))
ReviewDraft.shared.add(ReviewComment(file: "App.swift", line: 12,
                                     severity: .suggestion, note: "Extract this into a helper."))

print(ReviewDraft.shared.markdown())
// ## Code review
//
// ### App.swift
// - **[suggestion]** L12: Extract this into a helper.
// - **[must-fix]** L42: Force-unwrap can crash here.

ReviewDraft.shared.clear()
```

### Tracking reviewed files

```swift
import ReviewKit

let repo = URL(fileURLWithPath: "/path/to/repo")
ReviewSession.shared.toggle("App.swift", repo: repo)
ReviewSession.shared.isReviewed("App.swift", repo: repo)            // true
ReviewSession.shared.reviewedCount(in: ["App.swift"], repo: repo)   // 1

// After the change set moves on, drop stale entries; then clear the session.
ReviewSession.shared.prune(to: ["App.swift"], repo: repo)
ReviewSession.shared.prune(to: [], repo: repo)                      // no-op: a stash or branch hop, the marks stay
ReviewSession.shared.reset(repo: repo)

// Stamp a mark with the content it reviewed, and it answers only for that content.
ReviewSession.shared.markReviewed("App.swift", stamp: blobHash, repo: repo)
ReviewSession.shared.isReviewed("App.swift", stamp: blobHash, repo: repo)      // true
ReviewSession.shared.isReviewed("App.swift", stamp: editedHash, repo: repo)    // false: the agent edited it again
ReviewSession.shared.isReviewed("App.swift", repo: repo)                       // false: a stamped mark, an unstamped question
ReviewSession.shared.reviewedCount(in: paths, repo: repo) { stampOf($0) }      // N of M, per path's stamp
```

### Turn checkpoints

```swift
import ReviewKit

// One snapshot per turn START, filed under the repository the agent works in — a linked
// worktree or a second checkout, not necessarily the one on screen.
let store = TurnCheckpointStore.shared
store.record(
    TurnCheckpoint(id: turn.id, commit: snapshotSHA, capturedAt: .now, prompt: turn.prompt,
                   session: "Claude Code|/path/to/transcript.jsonl"),
    repo: repoURL)
store.hasCheckpoint(forTurn: turn.id, repo: repoURL)    // can this turn's diff be exact?
store.diffRange(forTurn: turn.id, repo: repoURL)        // (from, to): `to` is the next checkpoint
                                                        // of the SAME session, nil = working tree
store.repo(forTurn: turn.id)                            // which repository holds it
store.reset(repo: repoURL)                              // the repository's commits are gone

// Which turn each line appeared during. The snapshots are a timeline, not an author: the
// person's own edits in a turn's span count toward it. Another agent's turn is named beside
// it only while that agent kept taking turns after the span opened.
TurnAttribution.turns(forLinesOf: now, snapshots: fileAtEachCheckpoint, checkpoints: store.checkpoints(repo: repoURL))
LineOrigins.origins(of: versions)   // each line's first version; a rewrite past `diffBudget` is matched by content
```

Two agents in one repository interleave their turns; a span closes only at the next turn of its
own session, so neither cuts the other short. `record` trims to `historyLimit` (50) per repo and
returns the evicted ids so the caller can release their git refs.

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT

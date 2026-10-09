# Swift Review Kit

What a change did, for the person reviewing it: line-pinned review notes, facts a change establishes (destructive SQL, dependencies, tests), and the callers and tests a touched symbol reaches.

## Modules

Each module is its own library product: depend on the package, then only on the products you use.

| Module | What it is |
|---|---|
| [`ReviewKit`](Docs/Modules/ReviewKit.md) | A code-review pass over changed files: line-pinned comments as one Markdown block, and which files are marked reviewed. |
| [`ChangeFacts`](Docs/Modules/ChangeFacts.md) | What a change DID, as facts a reviewer can hold against a brief — destructive SQL, dependencies, tests — never a judgement. |
| [`BlastRadius`](Docs/Modules/BlastRadius.md) | For each symbol a diff touches, its callers and covering tests across the project. |

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-review-kit.git", from: "0.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "ReviewKit", package: "swift-review-kit"),
    ]),
]
```

## Usage

### ReviewKit

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

// Which files are reviewed, per repository, as the content they were reviewed at.
ReviewSession.shared.setRepo(repoURL)
ReviewSession.shared.markReviewed("App.swift", stamp: blobHash)
ReviewSession.shared.isReviewed("App.swift", stamp: editedHash)   // false once the agent edits it again

// Which commit opened which agent turn, per repository, so a turn's diff can be exact.
// Every call names the repository: a session's checkpoints live where its agent works.
TurnCheckpointStore.shared.record(
    TurnCheckpoint(id: turn.id, commit: snapshot, capturedAt: .now, prompt: turn.prompt,
                   session: "Claude Code|/path/to/transcript.jsonl"), repo: worktreeURL)
TurnCheckpointStore.shared.diffRange(forTurn: turn.id, repo: worktreeURL)
// (from: snapshot, to: the next checkpoint of the SAME session, or nil for the working tree)
TurnCheckpointStore.shared.repo(forTurn: turn.id)                   // the repository holding it
TurnCheckpointStore.shared.reset(repo: worktreeURL)                 // its commits are gone
```

### ChangeFacts

See [Docs/Modules/ChangeFacts.md](Docs/Modules/ChangeFacts.md).

### BlastRadius

```swift
import BlastRadius

// Analyze the impact of lines 20–22 changing in a file.
// The closure is your symbol source: given a UTF-16 character offset and the
// file text, return the enclosing-symbol breadcrumb trail (innermost last).
let impacts = BlastRadius.analyze(
    file: changedFileURL,
    root: projectRoot,
    changedLines: [20, 21, 22]
) { charOffset, text in
    mySymbolProvider.breadcrumbs(at: charOffset, in: text)
}

// One SymbolImpact per changed symbol that has any usages.
for impact in impacts {
    print("\(impact.symbol): \(impact.callers.count) callers, \(impact.tests.count) tests")
    for loc in impact.callers {
        print("  \(loc.file):\(loc.line)  \(loc.text)")   // loc.absPath opens the file
    }
}
```

Each module's full guide is `Docs/Modules/<Module>.md`.

## Notes

The modules were separate packages until 27 September 2026 (`swift-change-facts`, `swift-blast-radius`); their commits are kept here, so `git log --follow` traces any file back through them.

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT — see [LICENSE](LICENSE).

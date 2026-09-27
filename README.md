# Swift Review Kit

What a change did, for the person reviewing it: line-pinned review notes, facts a change establishes (destructive SQL, dependencies, tests), and the callers and tests a touched symbol reaches.

## Modules

Each module is its own library product: depend on the package, then only on the products you use.

| Module | What it is |
|---|---|
| [`ReviewKit`](Docs/Modules/ReviewKit.md) | A code-review pass over changed files: line-pinned comments as one Markdown block, and which files are marked reviewed. |
| [`ChangeFacts`](Docs/Modules/ChangeFacts.md) | What a change DID, as facts a reviewer can hold against a brief — destructive SQL, dependencies, tests — never a judgement. |
| [`BlastRadius`](Docs/Modules/BlastRadius.md) | For each symbol a diff touches, its callers and covering tests across the project. |

## Installation

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

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)

## History

The modules were separate packages until 27 September 2026 (`swift-change-facts`, `swift-blast-radius`); their commits are kept here, so `git log --follow` traces any file back through them.

## Licence

MIT — see [LICENSE](LICENSE).

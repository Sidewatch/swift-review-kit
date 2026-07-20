# Swift Review Kit

A tiny, dependency-free model layer for a code-review pass over a set of changed files — collect line-pinned comments and emit them as one clean markdown block, and track which files you've marked *reviewed* across relaunches. The verify-what-changed core behind Sidewatch's "Send to Agent" surface.

## Features

- 📝 **Line-pinned comments** — `ReviewComment` carries a `file`, `line`, `severity`, and `note`
- 🚦 **Severities** — `ReviewSeverity`: `must-fix`, `suggestion`, `question` (the raw value is the markdown label)
- 📤 **Markdown emit** — `ReviewDraft.markdown()` groups by file, sorts by line, and indents multi-line notes so they stay inside their bullet
- ✅ **Reviewed set** — `ReviewSession.toggle(_:)` / `markReviewed(_:_:)` / `reviewedCount(in:)` to walk a change set to completion (N of M)
- 💾 **Per-repo persistence** — `ReviewSession.setRepo(_:)` scopes the reviewed set per repository; it survives relaunch via `UserDefaults`
- 🧹 **Prune** — `ReviewSession.prune(to:)` drops reviewed entries no longer in the live change set
- 🪶 **Zero dependencies** — Foundation only
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Swift 5.9+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-review-kit.git", from: "1.0.0")
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

ReviewSession.shared.setRepo(URL(fileURLWithPath: "/path/to/repo"))
ReviewSession.shared.toggle("App.swift")
ReviewSession.shared.isReviewed("App.swift")            // true
ReviewSession.shared.reviewedCount(in: ["App.swift"])   // 1

// After the change set moves on, drop stale entries; then clear the session.
ReviewSession.shared.prune(to: ["App.swift"])
ReviewSession.shared.reset()
```

## License

MIT

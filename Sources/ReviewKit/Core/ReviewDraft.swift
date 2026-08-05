//
//  ReviewDraft.swift
//  SwiftReviewKit
//
//  A batch of review notes accumulated across files during one review pass, then
//  emitted as a single structured markdown block for a terminal agent to act on.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// A batch of review notes accumulated across files during one review pass, then
/// emitted as a single structured markdown block into the terminal for the agent
/// to act on. Part of the "Send to Agent" surface — Sidewatch composes precise
/// feedback; the terminal agent does the editing.
/// - Note: `@MainActor` states what was already true rather than adding a constraint —
///   this is UI state, and every caller in the app reaches it from the main thread
///   (verified: no call site sits inside a background dispatch). Isolating it makes the
///   compiler enforce that, instead of it holding by convention.
@MainActor
public final class ReviewDraft {

    /// The shared, process-wide draft.
    public static let shared = ReviewDraft()

    /// The accumulated comments, in the order they were added.
    public private(set) var comments: [ReviewComment] = []

    /// Fired whenever ``comments`` changes, so a UI can refresh.
    public var onChange: (() -> Void)?

    private init() {}

    /// Appends a comment and notifies ``onChange``.
    public func add(_ c: ReviewComment) { comments.append(c); onChange?() }

    /// Removes the comment at index `i` (a no-op if out of range) and notifies ``onChange``.
    public func remove(at i: Int) { guard comments.indices.contains(i) else { return }; comments.remove(at: i); onChange?() }

    /// Removes every comment and notifies ``onChange``.
    public func clear() { comments.removeAll(); onChange?() }

    /// The comments grouped by file, each file's notes sorted by line — the block sent to the agent.
    ///
    /// A note that carries a ``ReviewComment/hunk`` quotes it as a fenced block indented into
    /// the list item, so the agent sees the exact source the note is about. Notes without one
    /// emit precisely as before.
    ///
    /// - Returns: A markdown string, or an empty string when there are no comments.
    public func markdown() -> String {
        guard !comments.isEmpty else { return "" }
        var byFile: [String: [ReviewComment]] = [:]
        for c in comments { byFile[c.file, default: []].append(c) }
        var out = "## Code review\n\n"
        for file in byFile.keys.sorted() {
            out += "### \(file)\n"
            for c in byFile[file]!.sorted(by: { $0.line < $1.line }) {
                // Indent continuation lines so a multi-line note stays inside its
                // list item instead of escaping into a sibling bullet or file heading.
                let note = c.note.replacingOccurrences(of: "\n", with: "\n  ")
                let span = (c.endLine.map { $0 > c.line } ?? false) ? "L\(c.line)-L\(c.endLine!)" : "L\(c.line)"
                out += "- **[\(c.severity.rawValue)]** \(span): \(note)\n"
                if let hunk = c.hunk, !hunk.isEmpty {
                    // Two-space indent (the same one the note's continuation lines use) keeps the
                    // fence inside the list item; the blank line before it is what makes markdown
                    // read it as a code block rather than more paragraph text.
                    let quoted = hunk.components(separatedBy: "\n")
                        .map { $0.isEmpty ? "" : "  " + $0 }
                        .joined(separator: "\n")
                    out += "\n  ```\n\(quoted)\n  ```\n"
                }
            }
            out += "\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

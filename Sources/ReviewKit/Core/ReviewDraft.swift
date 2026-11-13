//
//  ReviewDraft.swift
//  ReviewKit
//
//  A batch of review notes accumulated across files during one review pass, then
//  emitted as a single structured markdown block for a terminal agent to act on.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// A batch of review notes accumulated across files during one review pass, then emitted as
/// a single structured markdown block into the terminal for the agent to act on: the app
/// composes precise feedback, the terminal agent does the editing. Main-actor UI state.
@MainActor
public final class ReviewDraft {

    /// The draft of no project: notes made with no folder open.
    public static let shared = ReviewDraft()

    /// One draft per project, by the project folder's path. Notes name their file relative to their
    /// project, so one queue for every project would count a project's notes in another's window,
    /// mark the other's `README.md`, and send them with its batch.
    private static var byProject: [String: ReviewDraft] = [:]

    /// The draft of the project at `path`; ``shared`` for nil or an empty path. The same draft every time.
    public static func draft(forProject path: String?) -> ReviewDraft {
        guard let path, !path.isEmpty else { return shared }
        if let existing = byProject[path] { return existing }
        let made = ReviewDraft()
        byProject[path] = made
        return made
    }

    /// Fired with the draft whenever ANY draft changes, after its own ``onChange``: one place for a
    /// host with several windows to hear every project's queue.
    public static var onAnyChange: ((ReviewDraft) -> Void)?

    /// Tells this draft's listener and the listener for every draft.
    private func changed() {
        onChange?()
        Self.onAnyChange?(self)
    }

    /// The accumulated comments, in the order they were added.
    public private(set) var comments: [ReviewComment] = []

    /// Fired whenever ``comments`` changes, so a UI can refresh.
    public var onChange: (() -> Void)?

    private init() {}

    /// Appends a comment and notifies ``onChange``.
    public func add(_ c: ReviewComment) { comments.append(c); changed() }

    /// Removes the comment at index `i` (a no-op if out of range) and notifies ``onChange``.
    public func remove(at i: Int) { guard comments.indices.contains(i) else { return }; comments.remove(at: i); changed() }

    /// Moves every note in `file` to follow a text edit, so a note stays on the code it was
    /// written about after lines are inserted or deleted above it. The rule is
    /// ``ReviewComment/remappingLines(editLine:spanEndLine:lineDelta:)``, the same one the
    /// editor applies to its diff bands (lines 1-based). ``onChange`` fires only when
    /// something moved; notes for other files are untouched.
    public func remapLines(inFile file: String, editLine: Int, spanEndLine: Int, lineDelta: Int) {
        guard lineDelta != 0 else { return }
        var moved = false
        comments = comments.map { c in
            guard c.file == file else { return c }
            let next = c.remappingLines(editLine: editLine, spanEndLine: spanEndLine, lineDelta: lineDelta)
            if next.line != c.line || next.endLine != c.endLine { moved = true }
            return next
        }
        if moved { changed() }
    }

    /// The 1-based lines in `file` that carry at least one note — what a gutter draws a marker
    /// for. Empty when the file has none, which is the common case and costs one pass.
    ///
    /// - Parameter file: The file to look up, keyed exactly as the notes were added.
    /// - Returns: The set of lines holding a note.
    public func noteLines(inFile file: String) -> Set<Int> {
        var lines = Set<Int>()
        for c in comments where c.file == file { lines.insert(c.line) }
        return lines
    }

    /// Removes every comment and notifies ``onChange``.
    public func clear() { comments.removeAll(); changed() }

    /// The comments grouped by file, each file's notes sorted by line — the block sent to the agent.
    ///
    /// A note that carries a ``ReviewComment/hunk`` quotes it as a fenced block indented into
    /// the list item, so the agent sees the exact source the note is about.
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
        return out.trimmed
    }
}

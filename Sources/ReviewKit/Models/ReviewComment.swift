//
//  ReviewComment.swift
//  ReviewKit
//
//  A single review note pinned to a file and line, with a severity and message.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A single review note pinned to a `file` and `line`, optionally carrying the source it
/// refers to.
///
/// Comments are collected in a ``ReviewDraft`` and emitted as one markdown block
/// for a terminal agent to act on. A note that carries its ``hunk`` quotes the code
/// verbatim, so the agent can act without re-reading the file and can't drift onto the
/// wrong lines if the file moved on since the note was written.
public struct ReviewComment {

    /// The path of the file the note refers to.
    public let file: String

    /// The line number the note is pinned to — the first line when it spans a range.
    public let line: Int

    /// The last line of the range the note covers, or `nil` for a single-line note.
    public let endLine: Int?

    /// The source the note refers to, verbatim and without a trailing newline, or `nil`
    /// when none was captured.
    public let hunk: String?

    /// How strongly the note wants the agent to act.
    public var severity: ReviewSeverity

    /// The reviewer's message.
    public var note: String

    /// True once the file changed and the source the note quotes (``hunk``) is nowhere in it any
    /// more: what the note was about has been rewritten or removed. It is kept for the person to
    /// read, marks no line, and is left out of what is sent.
    public var isOutdated = false

    /// A copy of this comment placed where its quoted source now stands in `lines` (the file's
    /// lines as they are now): moved with it when the code moved, marked ``isOutdated`` when the
    /// code is gone, and no longer outdated when it is back. A note that quotes nothing cannot be
    /// followed and is returned as it is.
    public func reanchored(in lines: [String]) -> ReviewComment {
        guard let hunk, !hunk.isEmpty else { return self }
        var moved = self
        guard let start = LineAnchor.relocate(quoted: hunk.components(separatedBy: "\n"), from: line, in: lines) else {
            moved.isOutdated = true
            return moved
        }
        moved = ReviewComment(
            file: file, line: start, endLine: endLine.map { $0 + (start - line) }, hunk: hunk, severity: severity, note: note)
        return moved
    }

    /// A copy of this comment with its line numbers moved to follow a text edit: at or above
    /// the edit → unchanged; below the replaced span → shifted by `lineDelta`; INSIDE the span
    /// → clamped to `editLine`. Unlike a diff band (which a git refresh restores), a note is
    /// something a person typed, so it survives the replacement, anchored where the edit began.
    /// `editLine` and `spanEndLine` are 1-based; `lineDelta` is lines gained (negative: lost).
    public func remappingLines(editLine: Int, spanEndLine: Int, lineDelta: Int) -> ReviewComment {
        guard lineDelta != 0 else { return self }
        func moved(_ n: Int) -> Int {
            if n <= editLine { return n }
            if n > spanEndLine { return max(1, n + lineDelta) }
            return editLine
        }
        let newLine = moved(line)
        let newEnd = endLine.map { max(moved($0), newLine) }
        guard newLine != line || newEnd != endLine else { return self }
        var moved = ReviewComment(
            file: file, line: newLine, endLine: newEnd, hunk: hunk,
            severity: severity, note: note)
        moved.isOutdated = isOutdated
        return moved
    }

    /// Creates a single-line review comment carrying no source.
    ///
    /// - Parameters:
    ///   - file: The path of the file the note refers to.
    ///   - line: The line number the note is pinned to.
    ///   - severity: How strongly the note wants the agent to act.
    ///   - note: The reviewer's message.
    public init(file: String, line: Int, severity: ReviewSeverity, note: String) {
        self.init(file: file, line: line, endLine: nil, hunk: nil, severity: severity, note: note)
    }

    /// Creates a review comment, optionally spanning `line...endLine` and quoting its source
    /// as `hunk`.
    public init(
        file: String, line: Int, endLine: Int?, hunk: String?,
        severity: ReviewSeverity, note: String
    ) {
        self.file = file
        self.line = line
        self.endLine = endLine
        self.hunk = hunk
        self.severity = severity
        self.note = note
    }
}

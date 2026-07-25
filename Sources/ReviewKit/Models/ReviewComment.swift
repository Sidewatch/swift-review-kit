//
//  ReviewComment.swift
//  SwiftReviewKit
//
//  A single review note pinned to a file and line, with a severity and message.
//
//  Created by David Sherlock on 7/9/26.
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

    /// Creates a review comment, optionally spanning a range and quoting its source.
    ///
    /// - Parameters:
    ///   - file: The path of the file the note refers to.
    ///   - line: The first line the note covers.
    ///   - endLine: The last line covered, or `nil` when the note is a single line.
    ///   - hunk: The source the note refers to, or `nil` to quote nothing.
    ///   - severity: How strongly the note wants the agent to act.
    ///   - note: The reviewer's message.
    public init(file: String, line: Int, endLine: Int?, hunk: String?,
                severity: ReviewSeverity, note: String) {
        self.file = file
        self.line = line
        self.endLine = endLine
        self.hunk = hunk
        self.severity = severity
        self.note = note
    }
}

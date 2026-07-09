//
//  ReviewComment.swift
//  SwiftReviewKit
//
//  A single review note pinned to a file and line, with a severity and message.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// A single review note pinned to a `file` and `line`.
///
/// Comments are collected in a ``ReviewDraft`` and emitted as one markdown block
/// for a terminal agent to act on.
public struct ReviewComment {

    /// The path of the file the note refers to.
    public let file: String

    /// The line number the note is pinned to.
    public let line: Int

    /// How strongly the note wants the agent to act.
    public var severity: ReviewSeverity

    /// The reviewer's message.
    public var note: String

    /// Creates a review comment.
    ///
    /// - Parameters:
    ///   - file: The path of the file the note refers to.
    ///   - line: The line number the note is pinned to.
    ///   - severity: How strongly the note wants the agent to act.
    ///   - note: The reviewer's message.
    public init(file: String, line: Int, severity: ReviewSeverity, note: String) {
        self.file = file
        self.line = line
        self.severity = severity
        self.note = note
    }
}

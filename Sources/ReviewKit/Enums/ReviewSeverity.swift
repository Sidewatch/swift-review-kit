//
//  ReviewSeverity.swift
//  SwiftReviewKit
//
//  How strongly a single review note wants the terminal agent to act on it.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// How strongly a ``ReviewComment`` wants the terminal agent to act on it.
///
/// The raw value is the label that appears in the emitted markdown, e.g.
/// `**[must-fix]**`.
public enum ReviewSeverity: String, CaseIterable {

    /// A blocking problem the agent should fix.
    case mustFix = "must-fix"

    /// A non-blocking improvement worth considering.
    case suggestion = "suggestion"

    /// An open question for the agent to answer.
    case question = "question"
}

//
//  TurnCheckpoint.swift
//  ReviewKit
//
//  The snapshot taken when an agent turn began.
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

/// The snapshot taken when an agent turn began.
///
/// One checkpoint marks the *start* of a turn; the turn's diff runs from it to the start of the
/// next turn, or to the live working tree for the turn still in progress. That means one
/// snapshot per turn rather than a pair, and no closing snapshot to miss if the app isn't
/// watching when a turn ends.
public struct TurnCheckpoint: Equatable {

    /// Stable identifier for the turn — also the last component of its git ref.
    public let id: String

    /// The commit captured when the turn began.
    public let commit: String

    /// When the checkpoint was taken.
    public let capturedAt: Date

    /// The prompt that opened the turn, for labelling it in a picker.
    public let prompt: String

    /// Creates a checkpoint record.
    ///
    /// - Parameters:
    ///   - id: Stable turn identifier, safe to use in a git ref.
    ///   - commit: The commit captured when the turn began.
    ///   - capturedAt: When the snapshot was taken.
    ///   - prompt: The prompt that opened the turn.
    public init(id: String, commit: String, capturedAt: Date, prompt: String) {
        self.id = id
        self.commit = commit
        self.capturedAt = capturedAt
        self.prompt = prompt
    }
}

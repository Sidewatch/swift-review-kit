//
//  TurnAttribution.swift
//  ReviewKit
//
//  Which agent turn each line of a file appeared during, from the turns' snapshots.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Which agent turn each line of a file appeared during, worked out from the snapshot taken as
/// each turn began (``TurnCheckpoint``).
///
/// The snapshots are a timeline of the file: a line first present in snapshot `k` appeared
/// between snapshot `k - 1` and snapshot `k` — after the turn that `k - 1` opened had begun.
/// A line present in the first snapshot predates everything recorded and has no turn. The span
/// is a time, not an author: the person's own edits in that span count toward the turn too.
///
/// Two agents in one repository take turns in one timeline. A span is the turn that opened it,
/// plus each other session's latest turn when that session also took a turn LATER — it was
/// still at work across the span. A session that took no later turn may have finished, and is
/// not named.
public enum TurnAttribution {
    /// For each line of `current` (line `n` is element `n - 1`, see ``LineOrigins``), the turns
    /// it appeared during: the turn that opened its span first, then any other session's turn
    /// running beside it. Empty for a line older than every snapshot.
    ///
    /// - Parameters:
    ///   - current: The file as it is now.
    ///   - snapshots: The file at each of `checkpoints`, nil where it did not exist; the same
    ///     count and order as `checkpoints`.
    ///   - checkpoints: The repository's turn checkpoints, oldest first, across every session.
    /// - Returns: One list per line of `current`, or no lists when the counts differ, there
    ///   are no checkpoints, or the file is past ``LineOrigins/maximumLines``.
    public static func turns(forLinesOf current: String, snapshots: [String?], checkpoints: [TurnCheckpoint]) -> [[TurnCheckpoint]] {
        guard !checkpoints.isEmpty, snapshots.count == checkpoints.count else { return [] }
        let origins = LineOrigins.origins(of: snapshots + [current])
        var spans: [Int: [TurnCheckpoint]] = [:]
        return origins.map { origin in
            guard origin > 0 else { return [] }
            if let known = spans[origin] { return known }
            let span = turns(openedAt: origin - 1, in: checkpoints)
            spans[origin] = span
            return span
        }
    }

    /// The turns running in the span `checkpoints[index]` opened: that turn, then each other
    /// session's latest turn before it whose session takes another turn after it.
    static func turns(openedAt index: Int, in checkpoints: [TurnCheckpoint]) -> [TurnCheckpoint] {
        let opening = checkpoints[index]
        let later = Set(checkpoints[(index + 1)...].map(\.session))
        var beside: [String: TurnCheckpoint] = [:]
        for checkpoint in checkpoints[..<index] where checkpoint.session != opening.session && later.contains(checkpoint.session) {
            beside[checkpoint.session] = checkpoint  // the last one before the span wins
        }
        return [opening] + beside.values.sorted { $0.capturedAt > $1.capturedAt }
    }
}

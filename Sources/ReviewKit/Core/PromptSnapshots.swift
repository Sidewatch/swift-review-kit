//
//  PromptSnapshots.swift
//  ReviewKit
//
//  Snapshots taken the moment a prompt was sent, held until the turn they open is seen.
//
//  Created by David Sherlock on 11/14/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Working-tree snapshots taken the instant an agent said a prompt was sent, each held for the
/// turn that prompt opens. A host that learns of a turn only by reading the transcript snapshots
/// late: the turn's first edits can land before it looks. A snapshot taken at the prompt is the
/// tree before any of them.
///
/// A snapshot is used once, by the next turn seen in its session and repository, and only while
/// it is fresh: one left over (the turn was seen before the snapshot finished, or the agent
/// stopped saying) would otherwise open a later turn with an older tree and show another turn's
/// edits as its own.
public struct PromptSnapshots: Equatable, Sendable {
    /// How long after it was taken a snapshot may still open a turn.
    public static let maxAge: TimeInterval = 15

    private struct Held: Equatable, Sendable {
        let commit: String
        let repo: String
        let taken: Date
    }

    private var held: [String: Held] = [:]

    /// A repository as one place however it is spelled: a host meets the same folder as
    /// `/var/…` from one caller and `/private/var/…` from another.
    private static func place(_ repo: URL) -> String { repo.resolvingSymlinksInPath().standardizedFileURL.path }

    /// Nothing held.
    public init() {}

    /// Whether a snapshot is held for `session`.
    public func isHolding(session: String) -> Bool { held[session] != nil }

    /// The snapshot held for `session`, if any; holding is not yet using.
    public func commit(heldFor session: String) -> String? { held[session]?.commit }

    /// Holds `commit`, taken in `repo` at `taken`, for the next turn of `session`. A later prompt's
    /// snapshot replaces an earlier one still held.
    public mutating func hold(commit: String, session: String, repo: URL, taken: Date = Date()) {
        held[session] = Held(commit: commit, repo: Self.place(repo), taken: taken)
    }

    /// The snapshot that opens the turn just seen in `session`, if one is held for `repo` and is
    /// no older than ``maxAge``. Whatever is held for the session is given up either way: the next
    /// turn has its own prompt.
    public mutating func take(session: String, repo: URL, now: Date = Date()) -> String? {
        guard let snapshot = held.removeValue(forKey: session), snapshot.repo == Self.place(repo),
            now.timeIntervalSince(snapshot.taken) <= Self.maxAge, now >= snapshot.taken.addingTimeInterval(-1)
        else { return nil }
        return snapshot.commit
    }
}

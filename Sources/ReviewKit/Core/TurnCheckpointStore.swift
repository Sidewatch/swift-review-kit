//
//  TurnCheckpointStore.swift
//  SwiftReviewKit
//
//  The per-repo record of which commit opened which agent turn, so a turn's diff can be
//  exact rather than inferred.
//
//  Created by David Sherlock on 7/25/26.
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

/// Per-repo record of turn checkpoints, persisted so a review survives relaunch.
///
/// - Important: Checkpoints are **forward-only**. A turn that ran before the app was watching
///   has no snapshot and can only ever be reviewed by inference; ``hasCheckpoint(forTurn:)``
///   is what a UI should ask before claiming a diff is exact.
///
/// - Note: State is persisted synchronously to `UserDefaults.standard` under
///   `sidewatch.turnCheckpoints`, mirroring ``ReviewSession``.
/// - Note: `@MainActor` states what was already true rather than adding a constraint —
///   this is UI state, and every caller in the app reaches it from the main thread
///   (verified: no call site sits inside a background dispatch). Isolating it makes the
///   compiler enforce that, instead of it holding by convention.
@MainActor
public final class TurnCheckpointStore {

    /// The shared, process-wide store.
    public static let shared = TurnCheckpointStore()

    /// Checkpoints per repo path, oldest first.
    private var byRepo: [String: [TurnCheckpoint]] = [:]
    private var repoKey = ""

    /// Fired whenever the current repo's checkpoints change.
    public var onChange: (() -> Void)?

    /// How many checkpoints to keep per repo. Each pins a whole tree, so an unbounded
    /// history would hold every tree the repo ever had.
    public static let historyLimit = 50

    private init() { load() }

    /// Points the store at a repository. Pass `nil` when no repo is open.
    public func setRepo(_ root: URL?) { repoKey = RepoKey.of(root) }

    /// The current repo's checkpoints, oldest first.
    public var checkpoints: [TurnCheckpoint] { byRepo[repoKey] ?? [] }

    /// The checkpoint recorded for `id`, or `nil` when the turn predates the app watching.
    public func checkpoint(forTurn id: String) -> TurnCheckpoint? {
        checkpoints.first { $0.id == id }
    }

    /// Whether `id` has a snapshot — i.e. whether its diff can be exact.
    public func hasCheckpoint(forTurn id: String) -> Bool { checkpoint(forTurn: id) != nil }

    /// Records a checkpoint, replacing any existing one for the same turn.
    ///
    /// Trims to ``historyLimit``, returning the ids dropped so the caller can release their
    /// git refs.
    ///
    /// - Parameter checkpoint: The checkpoint to record.
    /// - Returns: The ids evicted by the trim, if any.
    @discardableResult
    public func record(_ checkpoint: TurnCheckpoint) -> [String] {
        guard !repoKey.isEmpty else { return [] }
        var list = checkpoints.filter { $0.id != checkpoint.id }
        list.append(checkpoint)
        list.sort { $0.capturedAt < $1.capturedAt }

        let overflow = max(0, list.count - Self.historyLimit)
        let dropped = list.prefix(overflow).map(\.id)
        if overflow > 0 { list.removeFirst(overflow) }

        byRepo[repoKey] = list
        save()
        onChange?()
        return Array(dropped)
    }

    /// The span to diff for `id`: the turn's own commit, and the next turn's commit — or `nil`
    /// for the newest turn, meaning "compare against the live working tree".
    ///
    /// - Parameter id: The turn to resolve.
    /// - Returns: The `from`/`to` pair, or `nil` when the turn has no checkpoint.
    public func diffRange(forTurn id: String) -> (from: String, to: String?)? {
        let list = checkpoints
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        let next = index + 1 < list.count ? list[index + 1].commit : nil
        return (list[index].commit, next)
    }

    /// Forgets every checkpoint for the current repo, returning the ids dropped.
    @discardableResult
    public func reset() -> [String] {
        let dropped = checkpoints.map(\.id)
        byRepo.removeValue(forKey: repoKey)
        save()
        onChange?()
        return dropped
    }

    // MARK: - Persistence

    /// Writes the whole per-repo store to `UserDefaults.standard` as plist-safe dictionaries.
    private func save() {
        let flat = byRepo.mapValues { list in
            list.map { ["id": $0.id, "commit": $0.commit,
                        "at": $0.capturedAt.timeIntervalSince1970, "prompt": $0.prompt] as [String: Any] }
        }
        UserDefaults.standard.set(flat, forKey: "sidewatch.turnCheckpoints")
    }

    /// Restores the per-repo store (a no-op if absent, and skipping any malformed entry).
    private func load() {
        guard let flat = UserDefaults.standard.dictionary(forKey: "sidewatch.turnCheckpoints")
                as? [String: [[String: Any]]] else { return }
        byRepo = flat.mapValues { entries in
            entries.compactMap { entry in
                guard let id = entry["id"] as? String,
                      let commit = entry["commit"] as? String,
                      let at = entry["at"] as? TimeInterval else { return nil }
                return TurnCheckpoint(id: id, commit: commit,
                                      capturedAt: Date(timeIntervalSince1970: at),
                                      prompt: entry["prompt"] as? String ?? "")
            }
        }
    }
}

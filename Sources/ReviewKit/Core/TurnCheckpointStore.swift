//
//  TurnCheckpointStore.swift
//  ReviewKit
//
//  The per-repo record of which commit opened which agent turn, so a turn's diff can be
//  exact rather than inferred.
//
//  Created by David Sherlock on 7/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Per-repo record of turn checkpoints, persisted so a review survives relaunch.
///
/// Every call names the repository it is about, because a session's checkpoints live in the
/// repository the agent works in — a linked worktree, a second checkout — which need not be
/// the one the host is showing, and two windows may show two repositories at once. There is
/// no "current" repository.
///
/// - Important: Checkpoints are **forward-only**. A turn that ran before the app was watching
///   has no snapshot and can only ever be reviewed by inference; ``hasCheckpoint(forTurn:repo:)``
///   is what a UI should ask before claiming a diff is exact.
///
/// - Note: Main-actor UI state, persisted synchronously to `UserDefaults.standard` under
///   `sidewatch.turnCheckpoints`, mirroring ``ReviewSession``.
@MainActor
public final class TurnCheckpointStore {

    /// The shared, process-wide store.
    public static let shared = TurnCheckpointStore()

    /// Checkpoints per repo path, oldest first.
    private var byRepo: [String: [TurnCheckpoint]] = [:]

    /// Fired whenever any repository's checkpoints change.
    public var onChange: (() -> Void)?

    /// How many checkpoints to keep per repo. Each pins a whole tree, so an unbounded
    /// history would hold every tree the repo ever had.
    public static let historyLimit = 50

    private init() { load() }

    // MARK: - Reading

    /// `repo`'s checkpoints, oldest first.
    public func checkpoints(repo: URL) -> [TurnCheckpoint] { byRepo[RepoKey.of(repo)] ?? [] }

    /// The checkpoint recorded for `id` in `repo`, or `nil`.
    public func checkpoint(forTurn id: String, repo: URL) -> TurnCheckpoint? { checkpoints(repo: repo).first { $0.id == id } }

    /// Whether `id` has a snapshot in `repo`.
    public func hasCheckpoint(forTurn id: String, repo: URL) -> Bool { checkpoint(forTurn: id, repo: repo) != nil }

    /// The repository holding a checkpoint for `id`. A turn's checkpoints live where its agent
    /// works, which a window showing another checkout cannot know without asking; turn ids are
    /// unique, so at most one repository answers.
    public func repo(forTurn id: String) -> URL? {
        let key = byRepo.keys.sorted().first { key in !key.isEmpty && byRepo[key]?.contains { $0.id == id } == true }
        return key.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// The span to diff for `id`: the turn's own commit, and the commit of the next turn of the
    /// SAME session — or `nil` for that session's newest turn, meaning "compare against the live
    /// working tree". Another session's turn in between never closes the span: two agents in one
    /// repository would otherwise cut each other's turns short.
    ///
    /// - Parameters:
    ///   - id: The turn to resolve.
    ///   - repo: The repository the turn's checkpoints live in.
    /// - Returns: The `from`/`to` pair, or `nil` when the turn has no checkpoint.
    public func diffRange(forTurn id: String, repo: URL) -> (from: String, to: String?)? {
        Self.diffRange(forTurn: id, in: checkpoints(repo: repo))
    }

    private static func diffRange(forTurn id: String, in list: [TurnCheckpoint]) -> (from: String, to: String?)? {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        let mine = list[index]
        let next = list[(index + 1)...].first { $0.session == mine.session }?.commit
        return (mine.commit, next)
    }

    // MARK: - Writing

    /// Records a checkpoint in `repo`, replacing any existing one for the same turn.
    ///
    /// Trims to ``historyLimit``, returning the ids dropped so the caller can release their
    /// git refs.
    ///
    /// - Parameters:
    ///   - checkpoint: The checkpoint to record.
    ///   - repo: The repository the snapshot was taken in.
    /// - Returns: The ids evicted by the trim, if any.
    @discardableResult
    public func record(_ checkpoint: TurnCheckpoint, repo: URL) -> [String] {
        record(checkpoint, key: RepoKey.of(repo))
    }

    private func record(_ checkpoint: TurnCheckpoint, key: String) -> [String] {
        var list = (byRepo[key] ?? []).filter { $0.id != checkpoint.id }
        list.append(checkpoint)
        list.sort { $0.capturedAt < $1.capturedAt }

        let overflow = max(0, list.count - Self.historyLimit)
        let dropped = list.prefix(overflow).map(\.id)
        if overflow > 0 { list.removeFirst(overflow) }

        byRepo[key] = list
        save()
        onChange?()
        return Array(dropped)
    }

    /// Forgets every checkpoint for `repo`, returning the ids dropped — for a repository whose
    /// commits are gone (`.git` recreated, the folder re-cloned).
    @discardableResult
    public func reset(repo: URL) -> [String] { reset(key: RepoKey.of(repo)) }

    private func reset(key: String) -> [String] {
        let dropped = (byRepo[key] ?? []).map(\.id)
        byRepo.removeValue(forKey: key)
        save()
        onChange?()
        return dropped
    }

    // MARK: - Persistence

    /// Writes the whole per-repo store to `UserDefaults.standard` as plist-safe dictionaries.
    private func save() {
        let flat = byRepo.mapValues { list in
            list.map {
                [
                    "id": $0.id, "commit": $0.commit,
                    "at": $0.capturedAt.timeIntervalSince1970, "prompt": $0.prompt,
                    "session": $0.session,
                ] as [String: Any]
            }
        }
        UserDefaults.standard.set(flat, forKey: "sidewatch.turnCheckpoints")
    }

    /// Restores the per-repo store (a no-op if absent, and skipping any malformed entry).
    private func load() {
        guard
            let flat = UserDefaults.standard.dictionary(forKey: "sidewatch.turnCheckpoints")
                as? [String: [[String: Any]]]
        else { return }
        byRepo = flat.mapValues { entries in
            entries.compactMap { entry in
                guard let id = entry["id"] as? String,
                    let commit = entry["commit"] as? String,
                    let at = entry["at"] as? TimeInterval
                else { return nil }
                return TurnCheckpoint(
                    id: id, commit: commit,
                    capturedAt: Date(timeIntervalSince1970: at),
                    prompt: entry["prompt"] as? String ?? "",
                    session: entry["session"] as? String ?? "")
            }
        }
    }
}

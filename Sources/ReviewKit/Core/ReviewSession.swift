//
//  ReviewSession.swift
//  SwiftReviewKit
//
//  Run-scoped review state: which changed files you've marked reviewed, persisted
//  per-repo in UserDefaults so a review survives relaunch.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// Run-scoped review state: which changed files you've marked *reviewed*.
/// Turns "a pile of diffs" into a session you can walk to completion (N of M).
/// Persisted per-repo so a review survives relaunch; pruned to the live change set.
///
/// - Note: State is persisted synchronously to `UserDefaults.standard` (key
///   `sidewatch.reviewSession`) on every mutation. Not thread-safe — call from
///   one thread (in practice, the main thread).
/// - Note: `@MainActor` states what was already true rather than adding a constraint —
///   this is UI state, and every caller in the app reaches it from the main thread
///   (verified: no call site sits inside a background dispatch). Isolating it makes the
///   compiler enforce that, instead of it holding by convention.
@MainActor
public final class ReviewSession {

    /// The shared, process-wide session.
    public static let shared = ReviewSession()

    private var reviewedByRepo: [String: Set<String>] = [:]
    private var repoKey = ""

    /// Fired whenever the reviewed set changes (so the Changes list can refresh).
    public var onChange: (() -> Void)?

    private init() { load() }

    /// Scopes subsequent calls to the repository rooted at `root` (`nil` scopes
    /// to a shared "no repo" bucket).
    public func setRepo(_ root: URL?) { repoKey = root?.path ?? "" }

    /// The reviewed set for the current repo; setting it persists immediately.
    private var reviewed: Set<String> {
        get { reviewedByRepo[repoKey] ?? [] }
        set {
            // Drop empty entries so the persisted dictionary doesn't accumulate
            // a dead key for every repo ever opened.
            if newValue.isEmpty {
                reviewedByRepo.removeValue(forKey: repoKey)
            } else {
                reviewedByRepo[repoKey] = newValue
            }
            save()
        }
    }

    /// Whether `path` has been marked reviewed in the current repo.
    public func isReviewed(_ path: String) -> Bool { reviewed.contains(path) }

    /// Flips the reviewed state of `path` and notifies ``onChange``.
    public func toggle(_ path: String) {
        var r = reviewed
        if r.contains(path) { r.remove(path) } else { r.insert(path) }
        reviewed = r
        onChange?()
    }

    /// Marks `path` reviewed (or not, when `on` is `false`), notifying ``onChange`` only on a change.
    public func markReviewed(_ path: String, _ on: Bool = true) {
        var r = reviewed
        if on { r.insert(path) } else { r.remove(path) }
        guard r != reviewed else { return }
        reviewed = r
        onChange?()
    }

    /// Clears every reviewed file in the current repo, notifying ``onChange`` only if it wasn't already empty.
    public func reset() {
        guard !reviewed.isEmpty else { return }
        reviewed = []
        onChange?()
    }

    /// How many of `paths` are marked reviewed.
    public func reviewedCount(in paths: [String]) -> Int { paths.filter { reviewed.contains($0) }.count }

    /// Drop reviewed entries no longer present in the change set (a file that reverted
    /// to unchanged shouldn't linger as "reviewed"), notifying ``onChange`` only on a change.
    public func prune(to paths: Set<String>) {
        let r = reviewed.intersection(paths)
        if r != reviewed {
            reviewed = r
            onChange?()
        }
    }

    /// Writes the whole per-repo store to `UserDefaults.standard` (Set → Array for plist).
    private func save() {
        UserDefaults.standard.set(reviewedByRepo.mapValues { Array($0) }, forKey: "sidewatch.reviewSession")
    }
    /// Restores the per-repo store from `UserDefaults.standard` (a no-op if absent or malformed).
    private func load() {
        guard let flat = UserDefaults.standard.dictionary(forKey: "sidewatch.reviewSession") as? [String: [String]] else { return }
        reviewedByRepo = flat.mapValues { Set($0) }
    }
}

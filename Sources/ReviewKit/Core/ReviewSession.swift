//
//  ReviewSession.swift
//  ReviewKit
//
//  Run-scoped review state: which changed files you've marked reviewed, persisted
//  per-repo in UserDefaults so a review survives relaunch.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Run-scoped review state: which changed files are marked *reviewed*, so a pile of diffs
/// becomes a session walked to completion (N of M). Per-repo, pruned to the live change set.
///
/// A mark can carry a content stamp — the working-tree blob hash the host computes — and then
/// answers only for that content: the agent editing the file again changes its stamp, and the
/// file is no longer reviewed. The unstamped calls are the stamped ones with a nil stamp, so a
/// stamped mark never answers an unstamped question and an unstamped mark never answers a
/// stamped one.
///
/// - Note: Main-actor UI state, persisted synchronously to `UserDefaults` (key
///   `sidewatch.reviewSession`) on every mutation, so a review survives relaunch.
@MainActor
public final class ReviewSession {

    /// The shared, process-wide session, over the standard defaults.
    public static let shared = ReviewSession(defaults: .standard)

    private static let key = "sidewatch.reviewSession"

    private let defaults: UserDefaults
    private var marksByRepo: [String: [String: ReviewMark]] = [:]
    private var repoKey = ""

    /// Fired whenever the reviewed set changes (so the Changes list can refresh).
    public var onChange: (() -> Void)?

    /// A session persisted in `defaults`; the shared session uses the standard defaults.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        load()
    }

    /// Scopes subsequent calls to the repository rooted at `root` (`nil` scopes
    /// to a shared "no repo" bucket).
    public func setRepo(_ root: URL?) { repoKey = RepoKey.of(root) }

    /// The marks for the current repo; setting them persists immediately.
    private var marks: [String: ReviewMark] {
        get { marksByRepo[repoKey] ?? [:] }
        set {
            // Drop empty entries so the persisted dictionary doesn't accumulate
            // a dead key for every repo ever opened.
            if newValue.isEmpty {
                marksByRepo.removeValue(forKey: repoKey)
            } else {
                marksByRepo[repoKey] = newValue
            }
            save()
        }
    }

    // MARK: - Asking

    /// Whether `path` is marked reviewed as the content `stamp` names: a stored stamp matches
    /// only the same stamp, and a mark without one matches only a nil `stamp`.
    public func isReviewed(_ path: String, stamp: String?) -> Bool {
        guard let mark = marks[path] else { return false }
        return mark.stamp == stamp
    }

    /// Whether `path` is marked reviewed without a stamp.
    public func isReviewed(_ path: String) -> Bool { isReviewed(path, stamp: nil) }

    /// How many of `paths` are marked reviewed as the content `stamp` names for each.
    public func reviewedCount(in paths: [String], stamp: (String) -> String?) -> Int {
        paths.filter { isReviewed($0, stamp: stamp($0)) }.count
    }

    /// How many of `paths` are marked reviewed without a stamp.
    public func reviewedCount(in paths: [String]) -> Int { reviewedCount(in: paths) { _ in nil } }

    // MARK: - Marking

    /// Marks `path` reviewed as the content `stamp` names, replacing any earlier mark, and
    /// notifies ``onChange`` only on a change.
    public func markReviewed(_ path: String, stamp: String?) {
        let mark = ReviewMark(stamp: stamp)
        guard marks[path] != mark else { return }
        marks[path] = mark
        onChange?()
    }

    /// Marks `path` reviewed without a stamp (or not reviewed, when `on` is `false`),
    /// notifying ``onChange`` only on a change.
    public func markReviewed(_ path: String, _ on: Bool = true) {
        if on { markReviewed(path, stamp: nil) } else { remove(path) }
    }

    /// Flips `path` between reviewed as `stamp` and not reviewed, and notifies ``onChange``.
    /// A mark with another stamp counts as not reviewed, so the flip marks it as `stamp`.
    public func toggle(_ path: String, stamp: String?) {
        if isReviewed(path, stamp: stamp) { remove(path) } else { markReviewed(path, stamp: stamp) }
    }

    /// Flips the unstamped reviewed state of `path` and notifies ``onChange``.
    public func toggle(_ path: String) { toggle(path, stamp: nil) }

    /// Clears every reviewed file in the current repo, notifying ``onChange`` only if it wasn't already empty.
    public func reset() {
        guard !marks.isEmpty else { return }
        marks = [:]
        onChange?()
    }

    /// Drops reviewed entries no longer present in the change set (a file that reverted to
    /// unchanged shouldn't linger as "reviewed"), notifying ``onChange`` only on a change.
    ///
    /// An empty `paths` is a no-op: a snapshot with no changes at all is a stash or a
    /// checkout away from the branch under review, not a review outcome, and the marks must
    /// still be there when the changes come back.
    public func prune(to paths: Set<String>) {
        guard !paths.isEmpty else { return }
        let kept = marks.filter { paths.contains($0.key) }
        guard kept.count != marks.count else { return }
        marks = kept
        onChange?()
    }

    /// Drops the mark on `path`, notifying ``onChange`` only when there was one.
    private func remove(_ path: String) {
        guard marks[path] != nil else { return }
        marks[path] = nil
        onChange?()
    }

    // MARK: - Persistence

    /// Writes the whole per-repo store to the defaults.
    private func save() {
        defaults.set(ReviewMarkRecords.encode(marksByRepo), forKey: Self.key)
    }

    /// Restores the per-repo store from the defaults (a no-op if absent or malformed).
    private func load() {
        guard let marks = ReviewMarkRecords.decode(defaults.object(forKey: Self.key)) else { return }
        marksByRepo = marks
    }
}

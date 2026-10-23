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

    /// Fired whenever the reviewed set changes (so the Changes list can refresh).
    public var onChange: (() -> Void)?

    /// A session persisted in `defaults`; the shared session uses the standard defaults.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        load()
    }

    /// `repo`'s marks (nil names the shared "no repository" bucket). Every call names its
    /// repository: two windows on two repositories share this one session.
    private func marks(_ repo: URL?) -> [String: ReviewMark] { marksByRepo[RepoKey.of(repo)] ?? [:] }

    /// Replaces `repo`'s marks and persists; an empty set drops the repository's entry, so the
    /// stored dictionary keeps no dead key for every repository ever opened.
    private func setMarks(_ marks: [String: ReviewMark], _ repo: URL?) {
        let key = RepoKey.of(repo)
        if marks.isEmpty { marksByRepo.removeValue(forKey: key) } else { marksByRepo[key] = marks }
        save()
    }

    // MARK: - Asking

    /// Whether `path` in `repo` is marked reviewed as the content `stamp` names: a stored stamp
    /// matches only the same stamp, and a mark without one matches only a nil `stamp`.
    public func isReviewed(_ path: String, stamp: String?, repo: URL?) -> Bool {
        guard let mark = marks(repo)[path] else { return false }
        return mark.stamp == stamp
    }

    /// Whether `path` in `repo` is marked reviewed without a stamp.
    public func isReviewed(_ path: String, repo: URL?) -> Bool { isReviewed(path, stamp: nil, repo: repo) }

    /// How many of `paths` in `repo` are marked reviewed as the content `stamp` names for each.
    public func reviewedCount(in paths: [String], repo: URL?, stamp: (String) -> String?) -> Int {
        paths.filter { isReviewed($0, stamp: stamp($0), repo: repo) }.count
    }

    /// How many of `paths` in `repo` are marked reviewed without a stamp.
    public func reviewedCount(in paths: [String], repo: URL?) -> Int { reviewedCount(in: paths, repo: repo) { _ in nil } }

    // MARK: - Marking

    /// Marks `path` in `repo` reviewed as the content `stamp` names, replacing any earlier
    /// mark, and notifies ``onChange`` only on a change.
    public func markReviewed(_ path: String, stamp: String?, repo: URL?) {
        let mark = ReviewMark(stamp: stamp)
        var marks = marks(repo)
        guard marks[path] != mark else { return }
        marks[path] = mark
        setMarks(marks, repo)
        onChange?()
    }

    /// Marks `path` in `repo` reviewed without a stamp (or not reviewed, when `on` is false),
    /// notifying ``onChange`` only on a change.
    public func markReviewed(_ path: String, _ on: Bool = true, repo: URL?) {
        if on { markReviewed(path, stamp: nil, repo: repo) } else { remove(path, repo) }
    }

    /// Flips `path` in `repo` between reviewed as `stamp` and not reviewed, and notifies
    /// ``onChange``. A mark with another stamp counts as not reviewed, so the flip marks it.
    public func toggle(_ path: String, stamp: String?, repo: URL?) {
        if isReviewed(path, stamp: stamp, repo: repo) { remove(path, repo) } else { markReviewed(path, stamp: stamp, repo: repo) }
    }

    /// Flips the unstamped reviewed state of `path` in `repo` and notifies ``onChange``.
    public func toggle(_ path: String, repo: URL?) { toggle(path, stamp: nil, repo: repo) }

    /// Clears every reviewed file in `repo`, notifying ``onChange`` only if it wasn't already empty.
    public func reset(repo: URL?) {
        guard !marks(repo).isEmpty else { return }
        setMarks([:], repo)
        onChange?()
    }

    /// Drops `repo`'s reviewed entries no longer present in the change set (a file that reverted
    /// to unchanged shouldn't linger as "reviewed"), notifying ``onChange`` only on a change.
    ///
    /// An empty `paths` is a no-op: a snapshot with no changes at all is a stash or a
    /// checkout away from the branch under review, not a review outcome, and the marks must
    /// still be there when the changes come back.
    public func prune(to paths: Set<String>, repo: URL?) {
        guard !paths.isEmpty else { return }
        let marks = marks(repo)
        let kept = marks.filter { paths.contains($0.key) }
        guard kept.count != marks.count else { return }
        setMarks(kept, repo)
        onChange?()
    }

    /// Drops the mark on `path` in `repo`, notifying ``onChange`` only when there was one.
    private func remove(_ path: String, _ repo: URL?) {
        var marks = marks(repo)
        guard marks[path] != nil else { return }
        marks[path] = nil
        setMarks(marks, repo)
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

//
//  TurnCheckpointStoreTests.swift
//  ReviewKitTests
//
//  Tests for `TurnCheckpointStore`: one checkpoint per turn start, the 50-entry bound with
//  evicted ids returned, persistence per repository, per-session spans, and reset.
//
//  Created by David Sherlock on 7/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ReviewKit

// The store is main-actor isolated; XCTest runs a @MainActor test class on the main queue.
/// Tests for `TurnCheckpointStore`: one checkpoint per turn start, the 50-entry bound with
/// evicted ids returned, persistence per repository, per-session spans, and reset.
@MainActor
final class TurnCheckpointStoreTests: XCTestCase {

    private let store = TurnCheckpointStore.shared
    private var repo = URL(fileURLWithPath: "/tmp/ckpt-tests/unset")
    private var other = URL(fileURLWithPath: "/tmp/ckpt-tests/unset-other")

    override func setUp() {
        super.setUp()
        // The store is a process-wide singleton, so each test gets its own repo keys.
        repo = URL(fileURLWithPath: "/tmp/ckpt-tests/\(UUID().uuidString)")
        other = URL(fileURLWithPath: "/tmp/ckpt-tests/other-\(UUID().uuidString)")
        store.setRepo(repo)
    }

    override func tearDown() {
        store.reset()
        store.reset(repo: other)
        store.setRepo(nil)
        super.tearDown()
    }

    private func checkpoint(_ id: String, _ commit: String, secondsFromNow: TimeInterval, session: String = "") -> TurnCheckpoint {
        TurnCheckpoint(
            id: id, commit: commit,
            capturedAt: Date(timeIntervalSince1970: 1_000_000 + secondsFromNow),
            prompt: "prompt \(id)", session: session)
    }

    func testRecordAndLookup() {
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        XCTAssertTrue(store.hasCheckpoint(forTurn: "t1"))
        XCTAssertEqual(store.checkpoint(forTurn: "t1")?.commit, "aaa")
        XCTAssertFalse(store.hasCheckpoint(forTurn: "nope"))
    }

    func testCheckpointsAreKeptInCaptureOrderRegardlessOfInsertOrder() {
        store.record(checkpoint("t2", "bbb", secondsFromNow: 20))
        store.record(checkpoint("t1", "aaa", secondsFromNow: 10))
        XCTAssertEqual(store.checkpoints.map(\.id), ["t1", "t2"])
    }

    func testRecordingTheSameTurnTwiceReplacesRatherThanDuplicates() {
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        store.record(checkpoint("t1", "zzz", secondsFromNow: 5))
        XCTAssertEqual(store.checkpoints.count, 1)
        XCTAssertEqual(store.checkpoint(forTurn: "t1")?.commit, "zzz")
    }

    func testDiffRangeSpansToTheNextTurn() {
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        store.record(checkpoint("t2", "bbb", secondsFromNow: 10))
        let range = store.diffRange(forTurn: "t1")
        XCTAssertEqual(range?.from, "aaa")
        XCTAssertEqual(range?.to, "bbb")
    }

    func testDiffRangeForTheNewestTurnEndsAtTheWorkingTree() {
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        store.record(checkpoint("t2", "bbb", secondsFromNow: 10))
        let range = store.diffRange(forTurn: "t2")
        XCTAssertEqual(range?.from, "bbb")
        // nil `to` means "the live working tree" — the turn in progress has no closing snapshot.
        XCTAssertNil(range?.to)
    }

    func testDiffRangeIsNilForATurnThatPredatesWatching() {
        // Forward-only: a turn that ran before the app was watching has no snapshot, and the
        // UI must be able to tell that apart from a turn that changed nothing.
        XCTAssertNil(store.diffRange(forTurn: "ancient"))
    }

    func testDiffRangeClosesAtTheNextTurnOfTheSameSession() {
        // Two agents in one repository interleave: A1, then B1, then A2. A1's span must run to
        // A2, not be cut short at B1; B1 is its session's newest turn and runs to the tree.
        store.record(checkpoint("a1", "c1", secondsFromNow: 0, session: "Claude Code|/s/a.jsonl"))
        store.record(checkpoint("b1", "c2", secondsFromNow: 10, session: "Codex|/s/b.jsonl"))
        store.record(checkpoint("a2", "c3", secondsFromNow: 20, session: "Claude Code|/s/a.jsonl"))
        XCTAssertEqual(store.diffRange(forTurn: "a1")?.to, "c3")
        XCTAssertNil(store.diffRange(forTurn: "b1")?.to)
        XCTAssertNil(store.diffRange(forTurn: "a2")?.to)
    }

    func testCheckpointsWithoutASessionStillChain() {
        // Entries recorded before sessions were kept carry an empty session and close each other.
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        store.record(checkpoint("t2", "bbb", secondsFromNow: 10))
        XCTAssertEqual(store.diffRange(forTurn: "t1")?.to, "bbb")
    }

    func testEveryCallCanNameItsRepository() {
        // The capture path records into the session's OWN repository, which need not be the
        // current one; the current repo's list stays untouched.
        store.record(checkpoint("w1", "aaa", secondsFromNow: 0), repo: other)
        store.record(checkpoint("w2", "bbb", secondsFromNow: 10), repo: other)
        XCTAssertTrue(store.checkpoints.isEmpty)
        XCTAssertFalse(store.hasCheckpoint(forTurn: "w1"))
        XCTAssertTrue(store.hasCheckpoint(forTurn: "w1", repo: other))
        XCTAssertEqual(store.checkpoints(repo: other).map(\.id), ["w1", "w2"])
        XCTAssertEqual(store.checkpoint(forTurn: "w2", repo: other)?.commit, "bbb")
        XCTAssertEqual(store.diffRange(forTurn: "w1", repo: other)?.to, "bbb")
        XCTAssertNil(store.diffRange(forTurn: "w1"))
    }

    func testRepoForTurnFindsTheRepositoryHoldingIt() {
        store.record(checkpoint("here", "aaa", secondsFromNow: 0))
        store.record(checkpoint("there", "bbb", secondsFromNow: 0), repo: other)
        XCTAssertEqual(store.repo(forTurn: "here")?.path, repo.path)
        XCTAssertEqual(store.repo(forTurn: "there")?.path, other.path)
        XCTAssertNil(store.repo(forTurn: "nowhere"))
    }

    func testRepoForTurnPrefersTheCurrentRepository() {
        store.record(checkpoint("both", "aaa", secondsFromNow: 0))
        store.record(checkpoint("both", "bbb", secondsFromNow: 0), repo: other)
        XCTAssertEqual(store.repo(forTurn: "both")?.path, repo.path)
    }

    func testResetOfOneRepositoryLeavesTheOthers() {
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        store.record(checkpoint("w1", "bbb", secondsFromNow: 0), repo: other)
        XCTAssertEqual(store.reset(repo: other), ["w1"])
        XCTAssertTrue(store.checkpoints(repo: other).isEmpty)
        XCTAssertTrue(store.hasCheckpoint(forTurn: "t1"))
    }

    func testTheSessionIsPersisted() {
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0, session: "Claude Code|/s/a.jsonl"))
        let flat = UserDefaults.standard.dictionary(forKey: "sidewatch.turnCheckpoints") as? [String: [[String: Any]]]
        let entry = flat?[RepoKey.of(repo)]?.first
        XCTAssertEqual(entry?["session"] as? String, "Claude Code|/s/a.jsonl")
    }

    func testHistoryLimitEvictsOldestAndReportsWhatItDropped() {
        let limit = TurnCheckpointStore.historyLimit
        for i in 0..<limit {
            store.record(checkpoint("t\(i)", "c\(i)", secondsFromNow: TimeInterval(i)))
        }
        XCTAssertEqual(store.checkpoints.count, limit)

        let dropped = store.record(checkpoint("overflow", "cX", secondsFromNow: TimeInterval(limit)))
        // The caller needs the evicted ids so it can release their git refs, or the refs
        // would pin trees forever with nothing pointing at them.
        XCTAssertEqual(dropped, ["t0"])
        XCTAssertEqual(store.checkpoints.count, limit)
        XCTAssertFalse(store.hasCheckpoint(forTurn: "t0"))
        XCTAssertTrue(store.hasCheckpoint(forTurn: "overflow"))
    }

    func testCheckpointsAreScopedPerRepo() {
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        store.setRepo(other)
        XCTAssertTrue(store.checkpoints.isEmpty)
        XCTAssertFalse(store.hasCheckpoint(forTurn: "t1"))
        store.setRepo(repo)
    }

    func testRecordWithNoRepoIsIgnored() {
        store.setRepo(nil)
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        XCTAssertTrue(store.checkpoints.isEmpty)
        store.setRepo(repo)
    }

    func testResetReturnsTheIdsItDropped() {
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        store.record(checkpoint("t2", "bbb", secondsFromNow: 10))
        XCTAssertEqual(store.reset().sorted(), ["t1", "t2"])
        XCTAssertTrue(store.checkpoints.isEmpty)
    }

    func testRecordFiresOnChange() {
        var fired = 0
        store.onChange = { fired += 1 }
        defer { store.onChange = nil }
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        XCTAssertEqual(fired, 1)
    }
}

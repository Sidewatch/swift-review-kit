//
//  TurnCheckpointStoreTests.swift
//  Tests for SwiftReviewKit
//
//  Tests for `TurnCheckpointStore`: one checkpoint per turn start, the 50-entry bound with
//  evicted ids returned, persistence per repository, and reset.
//
//  Created by David Sherlock on 7/25/26.
//

import XCTest
@testable import ReviewKit

// The store is main-actor isolated; XCTest runs a @MainActor test class on the main queue.
/// Tests for `TurnCheckpointStore`: one checkpoint per turn start, the 50-entry bound with
/// evicted ids returned, persistence per repository, and reset.
@MainActor
final class TurnCheckpointStoreTests: XCTestCase {

    private let store = TurnCheckpointStore.shared

    override func setUp() {
        super.setUp()
        // The store is a process-wide singleton, so each test gets its own repo key.
        store.setRepo(URL(fileURLWithPath: "/tmp/ckpt-tests/\(UUID().uuidString)"))
    }

    override func tearDown() {
        store.reset()
        store.setRepo(nil)
        super.tearDown()
    }

    private func checkpoint(_ id: String, _ commit: String, secondsFromNow: TimeInterval) -> TurnCheckpoint {
        TurnCheckpoint(id: id, commit: commit,
                       capturedAt: Date(timeIntervalSince1970: 1_000_000 + secondsFromNow),
                       prompt: "prompt \(id)")
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
        store.setRepo(URL(fileURLWithPath: "/tmp/ckpt-tests/other-\(UUID().uuidString)"))
        XCTAssertTrue(store.checkpoints.isEmpty)
        XCTAssertFalse(store.hasCheckpoint(forTurn: "t1"))
    }

    func testRecordWithNoRepoIsIgnored() {
        store.setRepo(nil)
        store.record(checkpoint("t1", "aaa", secondsFromNow: 0))
        XCTAssertTrue(store.checkpoints.isEmpty)
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

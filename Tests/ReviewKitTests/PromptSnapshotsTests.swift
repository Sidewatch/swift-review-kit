//
//  PromptSnapshotsTests.swift
//  ReviewKitTests
//
//  A snapshot taken at the prompt opens the next turn of its session, once, while it is fresh.
//
//  Created by David Sherlock on 11/14/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ReviewKit

final class PromptSnapshotsTests: XCTestCase {
    private let repo = URL(fileURLWithPath: "/work/site")
    private let other = URL(fileURLWithPath: "/work/other")
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    func testASnapshotOpensTheNextTurnOfItsSessionOnce() {
        var snapshots = PromptSnapshots()
        XCTAssertNil(snapshots.take(session: "a", repo: repo, now: at))
        snapshots.hold(commit: "c1", session: "a", repo: repo, taken: at)
        XCTAssertTrue(snapshots.isHolding(session: "a"))
        XCTAssertNil(snapshots.take(session: "b", repo: repo, now: at.addingTimeInterval(2)), "another session's turn")
        XCTAssertEqual(snapshots.take(session: "a", repo: repo, now: at.addingTimeInterval(2)), "c1")
        XCTAssertNil(snapshots.take(session: "a", repo: repo, now: at.addingTimeInterval(3)), "used once")
        XCTAssertEqual(snapshots, PromptSnapshots())
    }

    func testAStaleSnapshotOpensNothingAndIsGivenUp() {
        var snapshots = PromptSnapshots()
        snapshots.hold(commit: "c1", session: "a", repo: repo, taken: at)
        XCTAssertNil(
            snapshots.take(session: "a", repo: repo, now: at.addingTimeInterval(PromptSnapshots.maxAge + 1)),
            "a snapshot left over would give a later turn an older tree")
        XCTAssertFalse(snapshots.isHolding(session: "a"), "and it is not kept for the turn after")
        snapshots.hold(commit: "c2", session: "a", repo: repo, taken: at)
        XCTAssertEqual(
            snapshots.take(session: "a", repo: repo, now: at.addingTimeInterval(PromptSnapshots.maxAge)), "c2", "fresh to the limit")
    }

    func testASnapshotOfAnotherRepositoryIsNotThisTurns() {
        var snapshots = PromptSnapshots()
        snapshots.hold(commit: "c1", session: "a", repo: other, taken: at)
        XCTAssertNil(snapshots.take(session: "a", repo: repo, now: at.addingTimeInterval(1)))
        XCTAssertFalse(snapshots.isHolding(session: "a"))
    }

    func testOneRepositorySpelledTwoWaysIsOneRepository() throws {
        let real = FileManager.default.temporaryDirectory.appendingPathComponent("prompt-snapshots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }
        let link = real.deletingLastPathComponent().appendingPathComponent("prompt-snapshots-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: link) }
        var snapshots = PromptSnapshots()
        snapshots.hold(commit: "c1", session: "a", repo: link, taken: at)
        XCTAssertEqual(snapshots.take(session: "a", repo: real.appendingPathComponent("sub/.."), now: at.addingTimeInterval(1)), "c1")
    }

    func testALaterPromptsSnapshotReplacesAnEarlierOne() {
        var snapshots = PromptSnapshots()
        snapshots.hold(commit: "c1", session: "a", repo: repo, taken: at)
        snapshots.hold(commit: "c2", session: "a", repo: repo, taken: at.addingTimeInterval(5))
        snapshots.hold(commit: "c9", session: "b", repo: repo, taken: at)
        XCTAssertEqual(snapshots.take(session: "a", repo: repo, now: at.addingTimeInterval(6)), "c2")
        XCTAssertEqual(snapshots.take(session: "b", repo: repo, now: at.addingTimeInterval(6)), "c9", "sessions do not share")
    }
}

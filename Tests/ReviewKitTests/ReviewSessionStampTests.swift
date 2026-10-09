//
//  ReviewSessionStampTests.swift
//  ReviewKitTests
//
//  Tests for `ReviewSession`'s content stamps: a mark answers only for the content it was made
//  against, an empty change set does not prune, and stamps survive a relaunch.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ReviewKit

/// Tests for `ReviewSession`'s content stamps: a mark answers only for the content it was made
/// against, an empty change set does not prune, and stamps survive a relaunch.
@MainActor
final class ReviewSessionStampTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!
    private let repo = URL(fileURLWithPath: "/tmp/review-kit-tests/stamps")

    override func setUp() {
        super.setUp()
        suite = "review-kit-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func session() -> ReviewSession {
        let s = ReviewSession(defaults: defaults)
        s.setRepo(repo)
        return s
    }

    func testAMarkAnswersOnlyForTheStampItWasMadeWith() {
        let s = session()
        s.markReviewed("App.swift", stamp: "blob-1")
        XCTAssertTrue(s.isReviewed("App.swift", stamp: "blob-1"))
        XCTAssertFalse(s.isReviewed("App.swift", stamp: "blob-2"), "the agent edited the file again")
        XCTAssertFalse(s.isReviewed("App.swift", stamp: nil), "a stamped mark never answers an unstamped question")
        XCTAssertFalse(s.isReviewed("App.swift"))

        s.markReviewed("Other.swift", stamp: nil)
        XCTAssertTrue(s.isReviewed("Other.swift", stamp: nil))
        XCTAssertTrue(s.isReviewed("Other.swift"))
        XCTAssertFalse(s.isReviewed("Other.swift", stamp: "blob-1"), "an unstamped mark never answers a stamped question")
        XCTAssertFalse(s.isReviewed("Missing.swift", stamp: nil))
    }

    func testReMarkingWithANewStampReplacesTheOldOneAndFiresOnlyOnAChange() {
        let s = session()
        var fired = 0
        s.onChange = { fired += 1 }
        s.markReviewed("App.swift", stamp: "blob-1")
        s.markReviewed("App.swift", stamp: "blob-1")  // same content → silent
        XCTAssertEqual(fired, 1)
        s.markReviewed("App.swift", stamp: "blob-2")  // re-reviewed after an edit → fires
        XCTAssertEqual(fired, 2)
        XCTAssertTrue(s.isReviewed("App.swift", stamp: "blob-2"))
        XCTAssertFalse(s.isReviewed("App.swift", stamp: "blob-1"))
    }

    func testToggleWithAStampMarksAStaleFileRatherThanClearingIt() {
        let s = session()
        s.markReviewed("App.swift", stamp: "blob-1")
        s.toggle("App.swift", stamp: "blob-2")
        XCTAssertTrue(s.isReviewed("App.swift", stamp: "blob-2"), "not reviewed as blob-2, so the flip marks it")
        s.toggle("App.swift", stamp: "blob-2")
        XCTAssertFalse(s.isReviewed("App.swift", stamp: "blob-2"))
        XCTAssertFalse(s.isReviewed("App.swift", stamp: "blob-1"), "the flip removed the mark")
    }

    func testReviewedCountTakesEachPathsStamp() {
        let s = session()
        s.markReviewed("a.swift", stamp: "a1")
        s.markReviewed("b.swift", stamp: "b1")
        s.markReviewed("c.swift", stamp: nil)
        let stamps = ["a.swift": "a1", "b.swift": "b2"]
        XCTAssertEqual(
            s.reviewedCount(in: ["a.swift", "b.swift", "c.swift"]) { stamps[$0] }, 2,
            "a.swift matches; b.swift was edited; c.swift is unstamped and asked without a stamp")
        XCTAssertEqual(
            s.reviewedCount(in: ["a.swift", "b.swift", "c.swift"]), 1,
            "the unstamped count is the stamped count with nil stamps: only c.swift")
    }

    func testPruneToAnEmptySetKeepsEveryMark() {
        let s = session()
        s.markReviewed("keep.swift", stamp: "k1")
        s.markReviewed("other.swift")
        var fired = 0
        s.onChange = { fired += 1 }
        s.prune(to: [])  // a stash or a branch hop: no changes at all, not a review outcome
        XCTAssertEqual(fired, 0)
        XCTAssertTrue(s.isReviewed("keep.swift", stamp: "k1"))
        XCTAssertTrue(s.isReviewed("other.swift"))
    }

    func testPruneToANonEmptySetStillDropsAbsentPaths() {
        let s = session()
        s.markReviewed("keep.swift", stamp: "k1")
        s.markReviewed("gone.swift", stamp: "g1")
        var fired = 0
        s.onChange = { fired += 1 }
        s.prune(to: ["keep.swift", "new.swift"])
        XCTAssertEqual(fired, 1)
        XCTAssertTrue(s.isReviewed("keep.swift", stamp: "k1"))
        XCTAssertFalse(s.isReviewed("gone.swift", stamp: "g1"))
        s.prune(to: ["keep.swift"])  // nothing dropped → silent
        XCTAssertEqual(fired, 1)
    }

    func testStampsSurviveARelaunch() {
        let first = session()
        first.markReviewed("stamped.swift", stamp: "blob-7")
        first.markReviewed("plain.swift")
        first.setRepo(nil)
        first.markReviewed("elsewhere.swift", stamp: "e1")

        let second = session()  // a fresh session over the same defaults, as after a relaunch
        XCTAssertTrue(second.isReviewed("stamped.swift", stamp: "blob-7"))
        XCTAssertFalse(second.isReviewed("stamped.swift", stamp: nil), "the stamp came back, not just the path")
        XCTAssertTrue(second.isReviewed("plain.swift", stamp: nil))
        XCTAssertFalse(second.isReviewed("plain.swift", stamp: ""), "an unstamped mark is not an empty stamp")
        second.setRepo(nil)
        XCTAssertTrue(second.isReviewed("elsewhere.swift", stamp: "e1"))

        let stored = defaults.dictionary(forKey: "sidewatch.reviewSession") as? [String: [String: String]]
        XCTAssertEqual(stored?[repo.path], ["stamped.swift": "blob-7", "plain.swift": ""])
    }

    func testTheOldPathListFormatIsNotRead() {
        defaults.set([repo.path: ["old.swift"]], forKey: "sidewatch.reviewSession")
        let s = session()
        XCTAssertFalse(s.isReviewed("old.swift"), "the pre-launch list form starts the marks empty, no migration")
    }
}

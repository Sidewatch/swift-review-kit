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
        return s
    }

    func testAMarkAnswersOnlyForTheStampItWasMadeWith() {
        let s = session()
        s.markReviewed("App.swift", stamp: "blob-1", repo: repo)
        XCTAssertTrue(s.isReviewed("App.swift", stamp: "blob-1", repo: repo))
        XCTAssertFalse(s.isReviewed("App.swift", stamp: "blob-2", repo: repo), "the agent edited the file again")
        XCTAssertFalse(s.isReviewed("App.swift", stamp: nil, repo: repo), "a stamped mark never answers an unstamped question")
        XCTAssertFalse(s.isReviewed("App.swift", repo: repo))

        s.markReviewed("Other.swift", stamp: nil, repo: repo)
        XCTAssertTrue(s.isReviewed("Other.swift", stamp: nil, repo: repo))
        XCTAssertTrue(s.isReviewed("Other.swift", repo: repo))
        XCTAssertFalse(s.isReviewed("Other.swift", stamp: "blob-1", repo: repo), "an unstamped mark never answers a stamped question")
        XCTAssertFalse(s.isReviewed("Missing.swift", stamp: nil, repo: repo))
    }

    func testReMarkingWithANewStampReplacesTheOldOneAndFiresOnlyOnAChange() {
        let s = session()
        var fired = 0
        s.onChange = { fired += 1 }
        s.markReviewed("App.swift", stamp: "blob-1", repo: repo)
        s.markReviewed("App.swift", stamp: "blob-1", repo: repo)  // same content → silent
        XCTAssertEqual(fired, 1)
        s.markReviewed("App.swift", stamp: "blob-2", repo: repo)  // re-reviewed after an edit → fires
        XCTAssertEqual(fired, 2)
        XCTAssertTrue(s.isReviewed("App.swift", stamp: "blob-2", repo: repo))
        XCTAssertFalse(s.isReviewed("App.swift", stamp: "blob-1", repo: repo))
    }

    func testToggleWithAStampMarksAStaleFileRatherThanClearingIt() {
        let s = session()
        s.markReviewed("App.swift", stamp: "blob-1", repo: repo)
        s.toggle("App.swift", stamp: "blob-2", repo: repo)
        XCTAssertTrue(s.isReviewed("App.swift", stamp: "blob-2", repo: repo), "not reviewed as blob-2, so the flip marks it")
        s.toggle("App.swift", stamp: "blob-2", repo: repo)
        XCTAssertFalse(s.isReviewed("App.swift", stamp: "blob-2", repo: repo))
        XCTAssertFalse(s.isReviewed("App.swift", stamp: "blob-1", repo: repo), "the flip removed the mark")
    }

    func testReviewedCountTakesEachPathsStamp() {
        let s = session()
        s.markReviewed("a.swift", stamp: "a1", repo: repo)
        s.markReviewed("b.swift", stamp: "b1", repo: repo)
        s.markReviewed("c.swift", stamp: nil, repo: repo)
        let stamps = ["a.swift": "a1", "b.swift": "b2"]
        XCTAssertEqual(
            s.reviewedCount(in: ["a.swift", "b.swift", "c.swift"], repo: repo) { stamps[$0] }, 2,
            "a.swift matches; b.swift was edited; c.swift is unstamped and asked without a stamp")
        XCTAssertEqual(
            s.reviewedCount(in: ["a.swift", "b.swift", "c.swift"], repo: repo), 1,
            "the unstamped count is the stamped count with nil stamps: only c.swift")
    }

    func testPruneToAnEmptySetKeepsEveryMark() {
        let s = session()
        s.markReviewed("keep.swift", stamp: "k1", repo: repo)
        s.markReviewed("other.swift", repo: repo)
        var fired = 0
        s.onChange = { fired += 1 }
        s.prune(to: [], repo: repo)  // a stash or a branch hop: no changes at all, not a review outcome
        XCTAssertEqual(fired, 0)
        XCTAssertTrue(s.isReviewed("keep.swift", stamp: "k1", repo: repo))
        XCTAssertTrue(s.isReviewed("other.swift", repo: repo))
    }

    func testPruneToANonEmptySetStillDropsAbsentPaths() {
        let s = session()
        s.markReviewed("keep.swift", stamp: "k1", repo: repo)
        s.markReviewed("gone.swift", stamp: "g1", repo: repo)
        var fired = 0
        s.onChange = { fired += 1 }
        s.prune(to: ["keep.swift", "new.swift"], repo: repo)
        XCTAssertEqual(fired, 1)
        XCTAssertTrue(s.isReviewed("keep.swift", stamp: "k1", repo: repo))
        XCTAssertFalse(s.isReviewed("gone.swift", stamp: "g1", repo: repo))
        s.prune(to: ["keep.swift"], repo: repo)  // nothing dropped → silent
        XCTAssertEqual(fired, 1)
    }

    func testStampsSurviveARelaunch() {
        let first = session()
        first.markReviewed("stamped.swift", stamp: "blob-7", repo: repo)
        first.markReviewed("plain.swift", repo: repo)
        first.markReviewed("elsewhere.swift", stamp: "e1", repo: nil)

        let second = session()  // a fresh session over the same defaults, as after a relaunch
        XCTAssertTrue(second.isReviewed("stamped.swift", stamp: "blob-7", repo: repo))
        XCTAssertFalse(second.isReviewed("stamped.swift", stamp: nil, repo: repo), "the stamp came back, not just the path")
        XCTAssertTrue(second.isReviewed("plain.swift", stamp: nil, repo: repo))
        XCTAssertFalse(second.isReviewed("plain.swift", stamp: "", repo: repo), "an unstamped mark is not an empty stamp")
        XCTAssertTrue(second.isReviewed("elsewhere.swift", stamp: "e1", repo: nil))

        let stored = defaults.dictionary(forKey: "sidewatch.reviewSession") as? [String: [String: String]]
        XCTAssertEqual(stored?[repo.path], ["stamped.swift": "blob-7", "plain.swift": ""])
    }

    func testTheOldPathListFormatIsNotRead() {
        defaults.set([repo.path: ["old.swift"]], forKey: "sidewatch.reviewSession")
        let s = session()
        XCTAssertFalse(s.isReviewed("old.swift", repo: repo), "the pre-launch list form starts the marks empty, no migration")
    }
}

//
//  ReviewKitTests.swift
//  Tests for SwiftReviewKit
//
//  Created by David Sherlock on 7/9/26.
//

import XCTest
@testable import ReviewKit

final class ReviewKitTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // The draft is a shared singleton — start each test from a clean slate
        // without letting the reset itself fire an observer left by a prior test.
        ReviewDraft.shared.onChange = nil
        ReviewDraft.shared.clear()
    }

    override func tearDown() {
        ReviewDraft.shared.onChange = nil
        ReviewDraft.shared.clear()
        super.tearDown()
    }

    // MARK: - ReviewDraft

    func testAddAppendsInOrder() {
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 1, severity: .mustFix, note: "one"))
        ReviewDraft.shared.add(ReviewComment(file: "b.swift", line: 2, severity: .question, note: "two"))
        XCTAssertEqual(ReviewDraft.shared.comments.count, 2)
        XCTAssertEqual(ReviewDraft.shared.comments.map(\.note), ["one", "two"])
    }

    func testAddFiresOnChange() {
        var fired = 0
        ReviewDraft.shared.onChange = { fired += 1 }
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 1, severity: .suggestion, note: "n"))
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 2, severity: .suggestion, note: "m"))
        XCTAssertEqual(fired, 2)
    }

    func testRemoveAtValidIndex() {
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 1, severity: .mustFix, note: "one"))
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 2, severity: .mustFix, note: "two"))
        ReviewDraft.shared.remove(at: 0)
        XCTAssertEqual(ReviewDraft.shared.comments.map(\.note), ["two"])
    }

    func testRemoveAtOutOfRangeIsNoOp() {
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 1, severity: .mustFix, note: "one"))
        var fired = 0
        ReviewDraft.shared.onChange = { fired += 1 }
        ReviewDraft.shared.remove(at: 5)     // out of range
        ReviewDraft.shared.remove(at: -1)    // out of range
        XCTAssertEqual(ReviewDraft.shared.comments.count, 1)
        XCTAssertEqual(fired, 0)
    }

    func testClearRemovesEverything() {
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 1, severity: .mustFix, note: "one"))
        ReviewDraft.shared.add(ReviewComment(file: "b.swift", line: 3, severity: .question, note: "two"))
        ReviewDraft.shared.clear()
        XCTAssertTrue(ReviewDraft.shared.comments.isEmpty)
    }

    func testMarkdownOnEmptyIsEmptyString() {
        XCTAssertEqual(ReviewDraft.shared.markdown(), "")
    }

    func testMarkdownGroupsByFileAndSortsByLine() {
        // Added out of order across two files; markdown groups by file (sorted) and
        // sorts each file's notes by line.
        ReviewDraft.shared.add(ReviewComment(file: "b.swift", line: 10, severity: .mustFix, note: "fix this"))
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 5, severity: .suggestion, note: "nit"))
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 2, severity: .question, note: "why?"))

        let expected = """
        ## Code review

        ### a.swift
        - **[question]** L2: why?
        - **[suggestion]** L5: nit

        ### b.swift
        - **[must-fix]** L10: fix this
        """
        XCTAssertEqual(ReviewDraft.shared.markdown(), expected)
    }

    func testSeverityRawValuesAppearInMarkdown() {
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 1, severity: .mustFix, note: "x"))
        let md = ReviewDraft.shared.markdown()
        XCTAssertTrue(md.contains("**[must-fix]**"))
        XCTAssertEqual(ReviewSeverity.allCases.map(\.rawValue), ["must-fix", "suggestion", "question"])
    }

    // MARK: - ReviewSession

    func testSessionToggleAndIsReviewed() {
        let repo = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        ReviewSession.shared.setRepo(repo)
        ReviewSession.shared.reset()

        XCTAssertFalse(ReviewSession.shared.isReviewed("App.swift"))
        ReviewSession.shared.toggle("App.swift")
        XCTAssertTrue(ReviewSession.shared.isReviewed("App.swift"))
        ReviewSession.shared.toggle("App.swift")
        XCTAssertFalse(ReviewSession.shared.isReviewed("App.swift"))

        ReviewSession.shared.reset()
    }

    func testSessionIsScopedPerRepo() {
        let repoA = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        let repoB = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")

        ReviewSession.shared.setRepo(repoA)
        ReviewSession.shared.toggle("Shared.swift")
        XCTAssertTrue(ReviewSession.shared.isReviewed("Shared.swift"))

        // A different repo doesn't see repoA's reviewed files.
        ReviewSession.shared.setRepo(repoB)
        XCTAssertFalse(ReviewSession.shared.isReviewed("Shared.swift"))

        // Back to repoA, the state is intact.
        ReviewSession.shared.setRepo(repoA)
        XCTAssertTrue(ReviewSession.shared.isReviewed("Shared.swift"))

        ReviewSession.shared.reset()
        ReviewSession.shared.setRepo(repoB)
        ReviewSession.shared.reset()
    }

    func testSessionReviewedCountAndReset() {
        let repo = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        ReviewSession.shared.setRepo(repo)
        ReviewSession.shared.reset()

        ReviewSession.shared.markReviewed("a.swift")
        ReviewSession.shared.markReviewed("b.swift")
        XCTAssertEqual(ReviewSession.shared.reviewedCount(in: ["a.swift", "b.swift", "c.swift"]), 2)

        ReviewSession.shared.reset()
        XCTAssertEqual(ReviewSession.shared.reviewedCount(in: ["a.swift", "b.swift"]), 0)
    }

    func testSessionMarkReviewedOffAndOnFiresOnChangeOnlyOnChange() {
        let repo = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        ReviewSession.shared.setRepo(repo)
        ReviewSession.shared.reset()

        var fired = 0
        ReviewSession.shared.onChange = { fired += 1 }
        ReviewSession.shared.markReviewed("a.swift", true)   // change → fires
        ReviewSession.shared.markReviewed("a.swift", true)   // no change → silent
        ReviewSession.shared.markReviewed("a.swift", false)  // change → fires
        XCTAssertEqual(fired, 2)

        ReviewSession.shared.onChange = nil
        ReviewSession.shared.reset()
    }

    func testSessionPruneDropsMissingPaths() {
        let repo = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        ReviewSession.shared.setRepo(repo)
        ReviewSession.shared.reset()

        ReviewSession.shared.markReviewed("keep.swift")
        ReviewSession.shared.markReviewed("gone.swift")
        ReviewSession.shared.prune(to: ["keep.swift"])
        XCTAssertTrue(ReviewSession.shared.isReviewed("keep.swift"))
        XCTAssertFalse(ReviewSession.shared.isReviewed("gone.swift"))

        ReviewSession.shared.reset()
    }
}

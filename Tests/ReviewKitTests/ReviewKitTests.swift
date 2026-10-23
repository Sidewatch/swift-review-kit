//
//  ReviewKitTests.swift
//  ReviewKitTests
//
//  Tests for `ReviewDraft`: notes accumulate per file, render to the markdown the agent
//  receives, and clear; the shared draft is reset around every test.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ReviewKit

/// Tests for `ReviewDraft`: notes accumulate per file, render to the markdown the agent
/// receives, and clear; the shared draft is reset around every test.
@MainActor
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
        ReviewDraft.shared.remove(at: 5)  // out of range
        ReviewDraft.shared.remove(at: -1)  // out of range
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

    func testMarkdownIndentsMultiLineNotesSoTheyStayInsideTheirListItem() {
        // A note with interior newlines must not escape its bullet — a continuation
        // line starting with "### " would otherwise read as a new file heading.
        ReviewDraft.shared.add(
            ReviewComment(
                file: "b.swift", line: 5, severity: .mustFix,
                note: "fix the loop\n### a.swift\nalso rename x"))
        let expected = """
            ## Code review

            ### b.swift
            - **[must-fix]** L5: fix the loop
              ### a.swift
              also rename x
            """
        XCTAssertEqual(ReviewDraft.shared.markdown(), expected)
        XCTAssertFalse(ReviewDraft.shared.markdown().contains("\n### a.swift"))
    }

    func testMarkdownQuotesTheHunkAsAFencedBlockInsideTheListItem() {
        ReviewDraft.shared.add(
            ReviewComment(
                file: "a.swift", line: 12, endLine: 14,
                hunk: "func go() {\n    return 1\n}",
                severity: .mustFix, note: "returns the wrong thing"))
        let expected = """
            ## Code review

            ### a.swift
            - **[must-fix]** L12-L14: returns the wrong thing

              ```
              func go() {
                  return 1
              }
              ```
            """
        XCTAssertEqual(ReviewDraft.shared.markdown(), expected)
    }

    func testMarkdownWithoutAHunkIsUnchanged() {
        // The pre-existing emission must be byte-identical for a note carrying no source —
        // no range suffix, no fence, no extra blank line.
        ReviewDraft.shared.add(ReviewComment(file: "a.swift", line: 5, severity: .suggestion, note: "nit"))
        let expected = """
            ## Code review

            ### a.swift
            - **[suggestion]** L5: nit
            """
        XCTAssertEqual(ReviewDraft.shared.markdown(), expected)
    }

    func testMarkdownOmitsTheRangeWhenTheNoteIsASingleLine() {
        // endLine equal to line is a single-line note, not a degenerate range.
        ReviewDraft.shared.add(
            ReviewComment(
                file: "a.swift", line: 7, endLine: 7, hunk: "let x = 1",
                severity: .question, note: "why?"))
        let md = ReviewDraft.shared.markdown()
        XCTAssertTrue(md.contains("- **[question]** L7: why?"))
        XCTAssertFalse(md.contains("L7-L7"))
        XCTAssertTrue(md.contains("  ```\n  let x = 1\n  ```"))
    }

    func testMarkdownHunkKeepsBlankLinesUnindented() {
        // Indenting an empty line would leave trailing whitespace inside the fence.
        ReviewDraft.shared.add(
            ReviewComment(
                file: "a.swift", line: 1, endLine: 3, hunk: "a\n\nb",
                severity: .mustFix, note: "n"))
        XCTAssertTrue(ReviewDraft.shared.markdown().contains("  ```\n  a\n\n  b\n  ```"))
    }

    func testEmptyHunkEmitsNoFence() {
        ReviewDraft.shared.add(
            ReviewComment(
                file: "a.swift", line: 1, endLine: nil, hunk: "",
                severity: .mustFix, note: "n"))
        XCTAssertFalse(ReviewDraft.shared.markdown().contains("```"))
    }

    func testLegacyInitStillCompilesAndCarriesNoSource() {
        let c = ReviewComment(file: "a.swift", line: 3, severity: .mustFix, note: "n")
        XCTAssertNil(c.endLine)
        XCTAssertNil(c.hunk)
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
        ReviewSession.shared.reset(repo: repo)

        XCTAssertFalse(ReviewSession.shared.isReviewed("App.swift", repo: repo))
        ReviewSession.shared.toggle("App.swift", repo: repo)
        XCTAssertTrue(ReviewSession.shared.isReviewed("App.swift", repo: repo))
        ReviewSession.shared.toggle("App.swift", repo: repo)
        XCTAssertFalse(ReviewSession.shared.isReviewed("App.swift", repo: repo))

        ReviewSession.shared.reset(repo: repo)
    }

    func testSessionIsScopedPerRepo() {
        let repoA = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        let repoB = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")

        ReviewSession.shared.toggle("Shared.swift", repo: repoA)
        XCTAssertTrue(ReviewSession.shared.isReviewed("Shared.swift", repo: repoA))

        // A different repo doesn't see repoA's reviewed files.
        XCTAssertFalse(ReviewSession.shared.isReviewed("Shared.swift", repo: repoB))

        // Back to repoA, the state is intact.
        XCTAssertTrue(ReviewSession.shared.isReviewed("Shared.swift", repo: repoA))

        ReviewSession.shared.reset(repo: repoA)
        ReviewSession.shared.reset(repo: repoB)
    }

    func testSessionReviewedCountAndReset() {
        let repo = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        ReviewSession.shared.reset(repo: repo)

        ReviewSession.shared.markReviewed("a.swift", repo: repo)
        ReviewSession.shared.markReviewed("b.swift", repo: repo)
        XCTAssertEqual(ReviewSession.shared.reviewedCount(in: ["a.swift", "b.swift", "c.swift"], repo: repo), 2)

        ReviewSession.shared.reset(repo: repo)
        XCTAssertEqual(ReviewSession.shared.reviewedCount(in: ["a.swift", "b.swift"], repo: repo), 0)
    }

    func testSessionMarkReviewedOffAndOnFiresOnChangeOnlyOnChange() {
        let repo = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        ReviewSession.shared.reset(repo: repo)

        var fired = 0
        ReviewSession.shared.onChange = { fired += 1 }
        ReviewSession.shared.markReviewed("a.swift", true, repo: repo)  // change → fires
        ReviewSession.shared.markReviewed("a.swift", true, repo: repo)  // no change → silent
        ReviewSession.shared.markReviewed("a.swift", false, repo: repo)  // change → fires
        XCTAssertEqual(fired, 2)

        ReviewSession.shared.onChange = nil
        ReviewSession.shared.reset(repo: repo)
    }

    func testSessionPruneDropsMissingPaths() {
        let repo = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        ReviewSession.shared.reset(repo: repo)

        ReviewSession.shared.markReviewed("keep.swift", repo: repo)
        ReviewSession.shared.markReviewed("gone.swift", repo: repo)
        ReviewSession.shared.prune(to: ["keep.swift"], repo: repo)
        XCTAssertTrue(ReviewSession.shared.isReviewed("keep.swift", repo: repo))
        XCTAssertFalse(ReviewSession.shared.isReviewed("gone.swift", repo: repo))

        ReviewSession.shared.reset(repo: repo)
    }

    func testSessionPruneFiresOnChangeOnlyOnChange() {
        let repo = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        ReviewSession.shared.reset(repo: repo)

        ReviewSession.shared.markReviewed("keep.swift", repo: repo)
        ReviewSession.shared.markReviewed("gone.swift", repo: repo)

        var fired = 0
        ReviewSession.shared.onChange = { fired += 1 }
        ReviewSession.shared.prune(to: ["keep.swift", "gone.swift"], repo: repo)  // nothing dropped → silent
        XCTAssertEqual(fired, 0)
        ReviewSession.shared.prune(to: ["keep.swift"], repo: repo)  // entry dropped → fires
        XCTAssertEqual(fired, 1)

        ReviewSession.shared.onChange = nil
        ReviewSession.shared.reset(repo: repo)
    }

    func testSessionEmptyRepoEntriesAreRemovedFromPersistedStore() {
        let repo = URL(fileURLWithPath: "/tmp/review-kit-tests/\(UUID().uuidString)")
        ReviewSession.shared.reset(repo: repo)

        ReviewSession.shared.markReviewed("a.swift", repo: repo)
        var persisted = UserDefaults.standard.dictionary(forKey: "sidewatch.reviewSession") as? [String: [String: String]]
        XCTAssertEqual(persisted?[repo.path], ["a.swift": ""])

        // Emptying the set must delete the repo's key, not persist a dead `[:]` entry.
        ReviewSession.shared.reset(repo: repo)
        persisted = UserDefaults.standard.dictionary(forKey: "sidewatch.reviewSession") as? [String: [String: String]]
        XCTAssertNil(persisted?[repo.path])
    }
}

/// Pins `RepoKey.of`: both stores file a repository under its path, and nil is the empty key.
final class RepoKeyTests: XCTestCase {
    func testBothStoresFileARepoUnderTheSameKey() {
        let root = URL(fileURLWithPath: "/tmp/repo")
        XCTAssertEqual(RepoKey.of(root), "/tmp/repo")
        XCTAssertEqual(RepoKey.of(nil), "")
    }
}

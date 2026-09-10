//
//  ReviewLineRemapTests.swift
//  SwiftReviewKit
//
//  Notes following a text edit: the rule that keeps a review note on the code it was
//  written about after lines move above it.
//
//  Created by David Sherlock on 9/11/26.
//

import XCTest
@testable import ReviewKit

/// Tests for `ReviewComment.remappingLines` and `ReviewDraft.remapLines`.
///
/// The three-way rule is the whole surface: at or above the edit is unchanged, below the
/// replaced span shifts, inside the span clamps. Each case is pinned separately because
/// collapsing them is exactly how an off-by-one hides.
final class ReviewLineRemapTests: XCTestCase {

    private func comment(_ line: Int, end: Int? = nil, file: String = "a.swift") -> ReviewComment {
        ReviewComment(file: file, line: line, endLine: end, hunk: nil, severity: .suggestion, note: "n")
    }

    // MARK: - The three-way rule

    func testLineAtOrAboveTheEditDoesNotMove() {
        // An insert on line 10 cannot move anything at or above line 10.
        XCTAssertEqual(comment(3).remappingLines(editLine: 10, spanEndLine: 10, lineDelta: 5).line, 3)
        XCTAssertEqual(comment(10).remappingLines(editLine: 10, spanEndLine: 10, lineDelta: 5).line, 10)
    }

    func testLineBelowTheReplacedSpanShiftsByTheDelta() {
        XCTAssertEqual(comment(40).remappingLines(editLine: 10, spanEndLine: 10, lineDelta: 10).line, 50)
        XCTAssertEqual(comment(40).remappingLines(editLine: 10, spanEndLine: 12, lineDelta: -2).line, 38)
    }

    func testLineInsideTheReplacedSpanClampsToTheEditLine() {
        // The note's anchor text was replaced. A diff band would be dropped here; a note the
        // user typed must survive, pinned where the edit began.
        let moved = comment(15).remappingLines(editLine: 10, spanEndLine: 20, lineDelta: -6)
        XCTAssertEqual(moved.line, 10)
    }

    // MARK: - Invariants

    func testZeroDeltaReturnsSelfUntouched() {
        let c = comment(7, end: 9)
        let same = c.remappingLines(editLine: 3, spanEndLine: 3, lineDelta: 0)
        XCTAssertEqual(same.line, 7)
        XCTAssertEqual(same.endLine, 9)
    }

    func testALineNeverFallsBelowOne() {
        // A deletion larger than the note's own line number must not produce line 0 or −3.
        XCTAssertEqual(comment(4).remappingLines(editLine: 1, spanEndLine: 1, lineDelta: -9).line, 1)
    }

    func testEndLineFollowsAndNeverPrecedesTheStart() {
        // Start clamps into the span while the end shifts: the end must not land above the start.
        let moved = comment(12, end: 30).remappingLines(editLine: 10, spanEndLine: 20, lineDelta: -8)
        XCTAssertEqual(moved.line, 10)
        XCTAssertGreaterThanOrEqual(moved.endLine ?? 0, moved.line)
    }

    // MARK: - Draft-level behaviour

    @MainActor
    func testRemapMovesOnlyTheNamedFileAndFiresOnChangeOnce() {
        let draft = ReviewDraft.shared
        draft.clear()
        draft.add(comment(40, file: "a.swift"))
        draft.add(comment(40, file: "b.swift"))
        var fired = 0
        draft.onChange = { fired += 1 }

        draft.remapLines(inFile: "a.swift", editLine: 10, spanEndLine: 10, lineDelta: 5)
        XCTAssertEqual(draft.comments.first { $0.file == "a.swift" }?.line, 45)
        XCTAssertEqual(draft.comments.first { $0.file == "b.swift" }?.line, 40, "another file's notes must not move")
        XCTAssertEqual(fired, 1)

        // Nothing to move → no redraw. A keystroke that changes no line numbers is the
        // common case and must not churn the notes list.
        draft.remapLines(inFile: "a.swift", editLine: 900, spanEndLine: 900, lineDelta: 5)
        XCTAssertEqual(fired, 1)
        draft.onChange = nil
        draft.clear()
    }

    @MainActor
    func testNoteLinesReportsEveryLineHoldingANote() {
        let draft = ReviewDraft.shared
        draft.clear()
        draft.add(comment(4)); draft.add(comment(9)); draft.add(comment(4))
        draft.add(comment(12, file: "other.swift"))
        XCTAssertEqual(draft.noteLines(inFile: "a.swift"), [4, 9])
        XCTAssertTrue(draft.noteLines(inFile: "nothing.swift").isEmpty)
        draft.clear()
    }
}

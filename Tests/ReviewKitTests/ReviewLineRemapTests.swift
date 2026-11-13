//
//  ReviewLineRemapTests.swift
//  ReviewKitTests
//
//  Notes following a text edit: the rule that keeps a review note on the code it was
//  written about after lines move above it.
//
//  Created by David Sherlock on 9/11/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
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

    // MARK: - Following the code after the file changed on disk

    private func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    func testQuotedLinesAreFoundNearestWhereTheyWere() {
        let file = lines("a\nb\nc\nb\nc\nd")
        XCTAssertEqual(LineAnchor.relocate(quoted: ["b", "c"], from: 2, in: file), 2, "where it was")
        XCTAssertEqual(LineAnchor.relocate(quoted: ["b", "c"], from: 5, in: file), 4, "of two places, the nearer")
        XCTAssertEqual(LineAnchor.relocate(quoted: ["b", "c"], from: 3, in: file), 2, "on a tie, the one above")
        XCTAssertEqual(LineAnchor.relocate(quoted: ["d"], from: 1, in: file), 6)
        XCTAssertNil(LineAnchor.relocate(quoted: ["b", "d"], from: 2, in: file), "the lines are there, but not together in that order")
        XCTAssertNil(LineAnchor.relocate(quoted: ["z"], from: 1, in: file))
        XCTAssertNil(LineAnchor.relocate(quoted: [""], from: 1, in: lines("a\n\nb")), "a blank quote could stand anywhere")
        XCTAssertNil(LineAnchor.relocate(quoted: [], from: 1, in: file))
        XCTAssertNil(LineAnchor.relocate(quoted: ["a", "b"], from: 1, in: ["a"]))
        XCTAssertEqual(
            LineAnchor.relocate(quoted: ["let x = 1  "], from: 9, in: ["let x = 1\r"]), 1, "trailing white space and a CR are not the code")
        XCTAssertNil(LineAnchor.relocate(quoted: ["  let x = 1"], from: 1, in: ["let x = 1"]), "indentation is")
    }

    func testANoteFollowsItsCodeOrGoesOutdated() {
        let note = ReviewComment(
            file: "a.swift", line: 2, endLine: 3, hunk: "func run() {\n    start()", severity: .mustFix, note: "rename")
        let inserted = note.reanchored(in: lines("import X\n\n// new\nfunc run() {\n    start()\n}"))
        XCTAssertEqual(inserted.line, 4)
        XCTAssertEqual(inserted.endLine, 5, "the range moves with its first line")
        XCTAssertFalse(inserted.isOutdated)
        let rewritten = note.reanchored(in: lines("import X\nfunc go() {\n    begin()\n}"))
        XCTAssertTrue(rewritten.isOutdated, "the code it was about is gone")
        XCTAssertEqual(rewritten.line, 2, "an outdated note keeps the line it had")
        let back = rewritten.reanchored(in: lines("func run() {\n    start()\n}"))
        XCTAssertFalse(back.isOutdated, "the code came back: so does the note")
        XCTAssertEqual(back.line, 1)
        let bare = ReviewComment(file: "a.swift", line: 7, severity: .mustFix, note: "no quote")
        XCTAssertEqual(bare.reanchored(in: ["x"]).line, 7, "a note that quotes nothing cannot be followed, and is left alone")
        XCTAssertFalse(bare.reanchored(in: ["x"]).isOutdated)
        XCTAssertTrue(rewritten.remappingLines(editLine: 1, spanEndLine: 1, lineDelta: 2).isOutdated, "an edit above keeps the mark")
    }

    @MainActor func testADraftSendsOnlyWhatIsNotOutdatedAndKeepsTheRest() {
        let draft = ReviewDraft.draft(forProject: "/projects/reanchor-\(UUID().uuidString)")
        var changes = 0
        draft.onChange = { changes += 1 }
        draft.add(ReviewComment(file: "a.swift", line: 1, endLine: nil, hunk: "alpha()", severity: .mustFix, note: "first"))
        draft.add(ReviewComment(file: "a.swift", line: 2, endLine: nil, hunk: "beta()", severity: .mustFix, note: "second"))
        draft.add(ReviewComment(file: "b.swift", line: 1, endLine: nil, hunk: "alpha()", severity: .mustFix, note: "other file"))
        changes = 0
        draft.reanchor(inFile: "a.swift", lines: ["// header", "alpha()", "gamma()"])
        XCTAssertEqual(changes, 1, "one notice for the file's notes")
        XCTAssertEqual(draft.comments.map(\.line), [2, 2, 1])
        XCTAssertEqual(draft.comments.map(\.isOutdated), [false, true, false], "another file's note is untouched")
        XCTAssertEqual(draft.outdatedCount, 1)
        XCTAssertEqual(draft.noteLines(inFile: "a.swift"), [2], "an outdated note marks no line")
        let sent = draft.markdown()
        XCTAssertTrue(sent.contains("first") && sent.contains("other file") && !sent.contains("second"), sent)
        draft.reanchor(inFile: "a.swift", lines: ["// header", "alpha()", "gamma()"])
        XCTAssertEqual(changes, 1, "nothing moved: nothing said")
        draft.clearSent()
        XCTAssertEqual(draft.comments.map(\.note), ["second"], "what was sent is gone; the outdated note stays to be read")
        XCTAssertEqual(draft.markdown(), "")
        draft.clear()
    }

    func testARemarkOnADiffLineFindsItsRowAgain() {
        let chunk = ["@@ -1,3 +1,4 @@", " keep", "+added one", "+added two", " keep"]
        XCTAssertEqual(DiffLineLocator.visibleIndex(ofText: "added two", side: "+", near: 2, in: chunk), 3)
        XCTAssertEqual(DiffLineLocator.visibleIndex(ofText: "keep", side: " ", near: 4, in: chunk), 4, "of two, the nearer")
        XCTAssertEqual(DiffLineLocator.visibleIndex(ofText: "keep", side: " ", near: 0, in: chunk), 1)
        XCTAssertNil(
            DiffLineLocator.visibleIndex(ofText: "added one", side: "-", near: 2, in: chunk),
            "the same words on the other side are another line")
        XCTAssertNil(DiffLineLocator.visibleIndex(ofText: "gone", side: "+", near: 2, in: chunk))
        let stale = [
            DiffReviewComment(path: "a", line: 1, side: "+", quoted: "x", text: "current"),
            {
                var c = DiffReviewComment(path: "a", line: 2, side: "+", quoted: "y", text: "stale")
                c.isOutdated = true
                return c
            }(),
        ]
        let message = DiffReviewMessage.format(stale, repoName: "repo")
        XCTAssertTrue(message.contains("current") && !message.contains("stale") && message.contains("(1)"), message)
        XCTAssertEqual(DiffReviewMessage.format([stale[1]], repoName: "repo"), "", "nothing but outdated remarks: nothing to send")
    }
}

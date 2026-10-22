//
//  LineOriginsTests.swift
//  ReviewKitTests
//
//  Tests for `LineOrigins`: each line of the newest version traced to the earliest version it
//  has been in unchanged.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ReviewKit

/// Tests for `LineOrigins`: each line of the newest version traced to the earliest version it
/// has been in unchanged.
final class LineOriginsTests: XCTestCase {

    func testOneVersionIsAllTheFirst() {
        XCTAssertEqual(LineOrigins.origins(of: ["a\nb"]), [0, 0])
    }

    func testInsertedAndEditedLinesStartWhereTheyFirstAppear() {
        let versions: [String?] = ["a\nb\nc", "a\nb\nNEW\nc", "a\nB2\nNEW\nc"]
        XCTAssertEqual(LineOrigins.origins(of: versions), [0, 2, 1, 0])
    }

    func testAnUnchangedVersionCarriesEveryOrigin() {
        let versions: [String?] = ["a", "a\nb", "a\nb", "a\nb\nc"]
        XCTAssertEqual(LineOrigins.origins(of: versions), [0, 1, 3])
    }

    func testALineRemovedAndWrittenAgainStartsAgain() {
        let versions: [String?] = ["a\nb\nc", "a\nc", "a\nb\nc"]
        XCTAssertEqual(LineOrigins.origins(of: versions), [0, 2, 0])
    }

    func testAFileThatDidNotExistYetStartsWhereItAppears() {
        XCTAssertEqual(LineOrigins.origins(of: [nil, nil, "x\ny"]), [2, 2])
        XCTAssertEqual(LineOrigins.origins(of: ["x", nil, "x"]), [2], "a deleted file written again starts again")
    }

    func testANewestVersionThatIsGoneHasNoLines() {
        XCTAssertEqual(LineOrigins.origins(of: ["a", nil]), [])
        XCTAssertEqual(LineOrigins.origins(of: []), [])
    }

    func testLinesAreNumberedAsGitNumbersThem() {
        // A trailing newline leaves a last, empty line; line n is element n - 1.
        XCTAssertEqual(LineOrigins.origins(of: ["a\n", "a\nb\n"]), [0, 1, 0])
    }

    func testALineEndingChangeIsAChange() {
        XCTAssertEqual(LineOrigins.origins(of: ["a\nb", "a\r\nb"]), [1, 0])
    }

    func testARewriteOfALargeFileIsMatchedByContentQuickly() {
        let old = (0..<20_000).map { "old \($0)" }
        var new = (0..<20_000).map { "new \($0)" }
        new[10] = "old 5"  // one line survives the rewrite, moved
        let start = Date()
        let origins = LineOrigins.origins(of: [old.joined(separator: "\n"), new.joined(separator: "\n")])
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0, "a line diff of this rewrite measured ~7 s")
        XCTAssertEqual(origins.count, 20_000)
        XCTAssertEqual(origins[10], 0, "the surviving line keeps its origin")
        XCTAssertEqual(origins.filter { $0 == 1 }.count, 19_999)
    }

    func testContentMatchingUsesEachOldLineOnce() {
        let origins = LineOrigins.carriedByContent([0, 1, 2], from: ["x", "x", "y"], to: ["x", "x", "x", "y"], newVersion: 5)
        XCTAssertEqual(origins, [0, 1, 5, 2])
    }

    func testUnsharedLinesCountRepeats() {
        XCTAssertEqual(LineOrigins.unsharedLines(["a", "a", "b"], ["a", "c"]), 3)
        XCTAssertEqual(LineOrigins.unsharedLines(["a", "b"], ["b", "a"]), 0)
    }

    func testAGeneratedFileIsNotTraced() {
        let huge = Array(repeating: "x", count: LineOrigins.maximumLines + 1).joined(separator: "\n")
        XCTAssertEqual(LineOrigins.origins(of: ["", huge]), [])
        let limit = Array(repeating: "x", count: LineOrigins.maximumLines).joined(separator: "\n")
        XCTAssertEqual(LineOrigins.origins(of: [limit]).count, LineOrigins.maximumLines)
    }
}

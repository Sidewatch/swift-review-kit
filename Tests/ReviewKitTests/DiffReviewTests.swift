//
//  DiffReviewTests.swift
//  ReviewKitTests
//
//  Ported from Sidewatch's --selftest-review: the mapping from a rendered diff line to a file
//  line, and the message the agent receives.
//
//  Created by David Sherlock on 9/5/26.
//

import XCTest
@testable import ReviewKit

/// Ported from Sidewatch's --selftest-review: the mapping from a rendered diff line to a
/// file line, and the message the agent receives.
final class DiffReviewTests: XCTestCase {
    let chunk = """
    diff --git a/src/main.py b/src/main.py
    index 1111111..2222222 100644
    --- a/src/main.py
    +++ b/src/main.py
    @@ -5,4 +5,5 @@ def main():
         config_path = "/etc/app.conf"
    -    config = load(config_path)
    +    config = load(config_path, strict=True)
    +    log.info("loaded")
         run(config)
    @@ -40,3 +41,3 @@ def helper():
         a = 1
    -    b = 2
    +    b = 3
         return a + b
    """.components(separatedBy: "\n")

    func testVisibleLinesAreHunkHeadersAndBodiesOnly() {
        XCTAssertEqual(DiffLineLocator.visibleLines(in: chunk).count, 11, "headers 2, bodies 9")
        XCTAssertEqual(DiffLineLocator.visibleLines(in: ["Binary files a and b differ"]).map(\.text), ["Binary files a and b differ"])
    }

    func testLocateMapsEveryKindOfLineToItsFileLine() {
        XCTAssertNil(DiffLineLocator.locate(chunk: chunk, visibleIndex: 0), "a hunk header has no file line")
        XCTAssertEqual(DiffLineLocator.locate(chunk: chunk, visibleIndex: 1), .init(line: 5, side: " ", text: "    config_path = \"/etc/app.conf\""))
        XCTAssertEqual(DiffLineLocator.locate(chunk: chunk, visibleIndex: 2), .init(line: 6, side: "-", text: "    config = load(config_path)"), "removed: OLD line number")
        XCTAssertEqual(DiffLineLocator.locate(chunk: chunk, visibleIndex: 3), .init(line: 6, side: "+", text: "    config = load(config_path, strict=True)"), "added: NEW line number")
        XCTAssertEqual(DiffLineLocator.locate(chunk: chunk, visibleIndex: 4), .init(line: 7, side: "+", text: "    log.info(\"loaded\")"))
        XCTAssertEqual(DiffLineLocator.locate(chunk: chunk, visibleIndex: 5), .init(line: 8, side: " ", text: "    run(config)"), "context after two adds is new 8 (old 7)")
        XCTAssertEqual(DiffLineLocator.locate(chunk: chunk, visibleIndex: 8)?.line, 41, "the second hunk restarts the counters")
        XCTAssertEqual(DiffLineLocator.locate(chunk: chunk, visibleIndex: 9), .init(line: 42, side: "+", text: "    b = 3"))
        XCTAssertNil(DiffLineLocator.locate(chunk: chunk, visibleIndex: 99))
    }

    func testMessageNumbersCommentsWithReferencesAndQuotes() {
        let message = DiffReviewMessage.format([
            DiffReviewComment(path: "src/main.py", line: 6, side: "+", quoted: "    config = load(config_path, strict=True)", text: "strict mode breaks the dev config"),
            DiffReviewComment(path: "src/main.py", line: nil, side: "", quoted: "", text: "add a docstring"),
        ], repoName: "demo")
        XCTAssertTrue(message.contains("Review comments (2) on demo"))
        XCTAssertTrue(message.contains("1. src/main.py:6 (added line)"))
        XCTAssertTrue(message.contains("`config = load(config_path, strict=True)`"))
        XCTAssertTrue(message.contains("2. src/main.py\n   → add a docstring"))
        XCTAssertEqual(DiffReviewMessage.format([], repoName: "demo"), "")
    }

    func testPRReviewPayloadPinsInlineCommentsAndFoldsTheRestIntoTheBody() throws {
        let inline = ReviewComment(file: "src/a.py", line: 3, severity: .mustFix, note: "off by one")
        let outside = ReviewComment(file: "docs/x.md", line: 1, severity: .suggestion, note: "typo\nsecond line")
        let data = try XCTUnwrap(PRReviewExporter.reviewPayload(inline: [inline], inBody: [outside]))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["event"] as? String, "COMMENT")
        let comments = try XCTUnwrap(obj["comments"] as? [[String: Any]])
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments[0]["path"] as? String, "src/a.py"); XCTAssertEqual(comments[0]["line"] as? Int, 3); XCTAssertEqual(comments[0]["side"] as? String, "RIGHT")
        XCTAssertEqual(comments[0]["body"] as? String, "**[\(ReviewSeverity.mustFix.rawValue)]** off by one")
        let body = try XCTUnwrap(obj["body"] as? String)
        XCTAssertTrue(body.contains("`docs/x.md:1`") && body.contains("typo\n  second line"), "continuation lines stay inside the bullet:\n\(body)")
        XCTAssertEqual(PRReviewExporter.bodyMarkdown([]), "")
    }

    func testRejectedPathsOnlyReturnsPathsTheAPIEchoedBack() {
        let body = Data(#"{"message":"Validation Failed","errors":[{"resource":"PullRequestReviewComment","message":"path docs/x.md is not part of the diff"}, "unrelated"]}"#.utf8)
        XCTAssertEqual(PRReviewExporter.rejectedPaths(inErrorBody: body, candidates: ["docs/x.md", "src/a.py"]), ["docs/x.md"])
        XCTAssertEqual(PRReviewExporter.rejectedPaths(inErrorBody: Data("not json".utf8), candidates: ["docs/x.md"]), [])
    }
}

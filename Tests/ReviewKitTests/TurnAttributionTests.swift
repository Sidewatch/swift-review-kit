//
//  TurnAttributionTests.swift
//  ReviewKitTests
//
//  Tests for `TurnAttribution`: each line of a file named by the turn it appeared during, with
//  a second agent's turn named only while that agent was still at work.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import ReviewKit

/// Tests for `TurnAttribution`: each line of a file named by the turn it appeared during, with
/// a second agent's turn named only while that agent was still at work.
final class TurnAttributionTests: XCTestCase {

    private func turn(_ id: String, session: String = "one", at seconds: TimeInterval) -> TurnCheckpoint {
        TurnCheckpoint(
            id: id, commit: "c-\(id)", capturedAt: Date(timeIntervalSince1970: seconds), prompt: "prompt \(id)", session: session)
    }

    private func ids(_ lists: [[TurnCheckpoint]]) -> [[String]] { lists.map { $0.map(\.id) } }

    func testEachLineIsNamedByTheTurnItAppearedDuring() {
        let checkpoints = [turn("t1", at: 1), turn("t2", at: 2), turn("t3", at: 3)]
        // t1 began on "a"; during t1 "b" appeared; during t2 "c"; during t3 (still running) "d".
        let snapshots: [String?] = ["a", "a\nb", "a\nb\nc"]
        let lists = TurnAttribution.turns(forLinesOf: "a\nb\nc\nd", snapshots: snapshots, checkpoints: checkpoints)
        XCTAssertEqual(ids(lists), [[], ["t1"], ["t2"], ["t3"]])
    }

    func testAnotherAgentStillAtWorkIsNamedBesideTheTurn() {
        // A1, then B1, then A2: a line that appeared between B1 and A2 could be either agent's,
        // since A was still taking turns. After A2, B took no later turn, so only A2 is named.
        let checkpoints = [turn("A1", session: "A", at: 1), turn("B1", session: "B", at: 2), turn("A2", session: "A", at: 3)]
        let snapshots: [String?] = ["base", "base\nx", "base\nx\ny"]
        let lists = TurnAttribution.turns(forLinesOf: "base\nx\ny\nz", snapshots: snapshots, checkpoints: checkpoints)
        XCTAssertEqual(ids(lists), [[], ["A1"], ["B1", "A1"], ["A2"]])
    }

    func testTheOtherAgentsLatestTurnIsTheOneNamed() {
        let checkpoints = [
            turn("A1", session: "A", at: 1), turn("A2", session: "A", at: 2), turn("B1", session: "B", at: 3),
            turn("A3", session: "A", at: 4),
        ]
        let lists = TurnAttribution.turns(forLinesOf: "a\nb", snapshots: ["a", "a", "a", "a\nb"], checkpoints: checkpoints)
        XCTAssertEqual(ids(lists), [[], ["B1", "A2"]])
    }

    func testAFinishedAgentIsNotNamed() {
        // B's only turn came before A's two; B took no later turn, so it is not named beside A2.
        let checkpoints = [turn("B1", session: "B", at: 1), turn("A1", session: "A", at: 2), turn("A2", session: "A", at: 3)]
        let lists = TurnAttribution.turns(forLinesOf: "a\nb", snapshots: ["a", "a", "a"], checkpoints: checkpoints)
        XCTAssertEqual(ids(lists), [[], ["A2"]])
    }

    func testNothingIsAttributedWithoutMatchingSnapshots() {
        XCTAssertEqual(TurnAttribution.turns(forLinesOf: "a", snapshots: [], checkpoints: []).count, 0)
        XCTAssertEqual(TurnAttribution.turns(forLinesOf: "a", snapshots: ["a"], checkpoints: []).count, 0)
        XCTAssertEqual(TurnAttribution.turns(forLinesOf: "a", snapshots: [], checkpoints: [turn("t1", at: 1)]).count, 0)
    }

    func testAFileCreatedDuringATurnIsThatTurns() {
        let checkpoints = [turn("t1", at: 1), turn("t2", at: 2)]
        let lists = TurnAttribution.turns(forLinesOf: "new\nfile", snapshots: [nil, "new\nfile"], checkpoints: checkpoints)
        XCTAssertEqual(ids(lists), [["t1"], ["t1"]])
    }
}

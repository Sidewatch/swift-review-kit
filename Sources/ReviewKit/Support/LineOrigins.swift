//
//  LineOrigins.swift
//  ReviewKit
//
//  For each line of a file's newest version, the earliest version it has been in unchanged.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// For each line of a file's newest version, the earliest of its versions the line has been in
/// unchanged ever since — what `git blame` answers over commits, answered over any sequence of
/// texts (a turn's snapshots, which are not a commit chain).
///
/// Each step is a line diff of one version against the next (the standard library's
/// `difference(from:)`): a line the next version inserts starts there, a line it keeps carries its
/// origin over. A line removed and later written again starts again. Lines are compared whole,
/// line endings included, and identical lines (a blank, a lone `}`) are matched the way any line
/// diff matches them. A step that rewrote most of a large file is matched by content instead
/// (``diffBudget``), since a line diff of it would take seconds.
public enum LineOrigins {
    /// Lines in the newest version beyond which no origins are worked out (a generated file).
    public static let maximumLines = 50_000

    /// The origin of every line of the last of `versions`: the index into `versions` of the
    /// earliest version that line has been in, unchanged, ever since. A nil version is a file
    /// that did not exist then. Empty when `versions` is empty or the newest version is nil or
    /// longer than ``maximumLines``.
    ///
    /// Lines are split on `\n`, so a text ending in a newline has a last, empty line, as git
    /// numbers them all the same: line `n` of the file is element `n - 1`.
    public static func origins(of versions: [String?]) -> [Int] {
        guard let newest = versions.last ?? nil else { return [] }
        let newestCount = newest.lines.count
        guard newestCount <= maximumLines else { return [] }
        var previous = versions[0]?.lines ?? []
        var origins = Array(repeating: 0, count: previous.count)
        for index in versions.indices.dropFirst() {
            let lines = versions[index]?.lines ?? []
            origins = carried(origins, from: previous, to: lines, newVersion: index)
            previous = lines
        }
        return origins
    }

    /// The line diff's work, estimated as (lines in both versions) × (lines only one of them
    /// has), past which a step matches lines by content instead. A line diff is quadratic in a
    /// rewrite: a 10,000-line file rewritten whole measured 1.75 s for one step, against under
    /// a millisecond for a few edits.
    public static let diffBudget = 5_000_000

    /// `origins` (one per line of `old`) carried onto `new`: kept lines keep theirs, inserted
    /// lines take `newVersion`. Past ``diffBudget`` it is ``carriedByContent(_:from:to:newVersion:)``.
    static func carried(_ origins: [Int], from old: [String], to new: [String], newVersion: Int) -> [Int] {
        guard old != new else { return origins }
        guard (old.count + new.count) * unsharedLines(old, new) <= diffBudget else {
            return carriedByContent(origins, from: old, to: new, newVersion: newVersion)
        }
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result: [Int] = []
        result.reserveCapacity(new.count)
        var oldIndex = 0
        for newIndex in new.indices {
            if inserted.contains(newIndex) {
                result.append(newVersion)
                continue
            }
            while removed.contains(oldIndex) { oldIndex += 1 }
            result.append(origins[oldIndex])
            oldIndex += 1
        }
        return result
    }

    /// How many lines one version has that the other lacks, counting repeats — the least edit
    /// distance a line diff can find, so a cheap floor for its work.
    static func unsharedLines(_ old: [String], _ new: [String]) -> Int {
        var counts: [String: Int] = [:]
        for line in old { counts[line, default: 0] += 1 }
        for line in new { counts[line, default: 0] -= 1 }
        return counts.values.reduce(0) { $0 + abs($1) }
    }

    /// A step matched by content, in linear time: each line of `new` takes the origin of the
    /// first unused line of `old` with the same text, and a line `old` has no copy of left
    /// starts at `newVersion`. Order is not considered, so a line moved keeps its origin.
    static func carriedByContent(_ origins: [Int], from old: [String], to new: [String], newVersion: Int) -> [Int] {
        var unused: [String: ArraySlice<Int>] = [:]
        for (index, line) in old.enumerated() { unused[line, default: []].append(index) }
        return new.map { line in
            guard let index = unused[line]?.popFirst() else { return newVersion }
            return origins[index]
        }
    }
}

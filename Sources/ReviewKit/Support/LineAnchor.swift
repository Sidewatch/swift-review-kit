//
//  LineAnchor.swift
//  ReviewKit
//
//  Finds where quoted lines stand in a file that has changed since they were quoted.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A remark is made about lines of code, and it keeps their text. When the file changes under it
/// (an agent's next turn), the text says where the remark belongs now, or that what it was about
/// is no longer there.
public enum LineAnchor {

    /// The 1-based line where `quoted` (one or more whole lines) now starts in `lines`: the place
    /// nearest `oldLine` where every quoted line stands in order, compared without trailing white
    /// space. Nil when the block is nowhere (the code was changed or removed), and for a quote that
    /// is empty or all blank, which could stand anywhere.
    public static func relocate(quoted: [String], from oldLine: Int, in lines: [String]) -> Int? {
        let wanted = quoted.map(trimmedEnd)
        guard !wanted.isEmpty, wanted.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }), wanted.count <= lines.count
        else { return nil }
        let have = lines.map(trimmedEnd)
        func stands(at start: Int) -> Bool {
            start >= 0 && start + wanted.count <= have.count && (0..<wanted.count).allSatisfy { have[start + $0] == wanted[$0] }
        }
        let origin = oldLine - 1
        // Outward from where it was: the nearest standing block wins, the one above on a tie.
        // As far as the farther end of the file from where it was, which may now lie past the file's end.
        for distance in 0...max(have.count, abs(origin) + 1) {
            if stands(at: origin - distance) { return origin - distance + 1 }
            if distance > 0, stands(at: origin + distance) { return origin + distance + 1 }
        }
        return nil
    }

    /// `line` without the white space and line ending at its end: a file that changed its line
    /// endings or lost trailing spaces still holds the same code.
    static func trimmedEnd(_ line: String) -> String {
        var end = line.endIndex
        while end > line.startIndex, let last = line[line.index(before: end)].unicodeScalars.first,
            CharacterSet.whitespacesAndNewlines.contains(last)
        {
            end = line.index(before: end)
        }
        return String(line[..<end])
    }
}

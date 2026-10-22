//
//  DiffLineLocator.swift
//  ReviewKit
//
//  Maps a rendered unified-diff line back to a file line, so a click on the Nth visible line of
//  a chunk can say "src/main.py:7, added".
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Maps a rendered unified-diff line back to a file line, so a click on the Nth visible line
/// of a chunk can say "src/main.py:7, added".
public enum DiffLineLocator {
    /// A located diff line: where it lives in the file and what it says.
    public struct Located: Equatable, Sendable {
        /// The 1-based line in the new file (old file for a removed line).
        public let line: Int
        /// "+", "-" or " ": added, removed or context.
        public let side: String
        /// The line's text without its diff marker.
        public let text: String
        /// A located line.
        public init(line: Int, side: String, text: String) { self.line = line; self.side = side; self.text = text }
    }

    /// The chunk lines a diff view renders, in order, with their index in the chunk: hunk
    /// headers and hunk bodies; pre-hunk headers are dropped except a "Binary files" note. The
    /// renderer MUST use this same list, or the selection→line mapping drifts.
    public static func visibleLines(in chunk: [String]) -> [(index: Int, text: String)] {
        var out: [(Int, String)] = []
        var inHunk = false
        for (i, raw) in chunk.enumerated() {
            if raw.hasPrefix("@@") { inHunk = true; out.append((i, raw)); continue }
            guard inHunk else {
                if raw.hasPrefix("Binary files") { out.append((i, raw)) }
                continue
            }
            out.append((i, raw))
        }
        return out
    }

    /// The file line behind the `visibleIndex`-th rendered diff line (0-based, banner excluded).
    /// Nil for hunk headers, binary notes and "\ No newline" markers.
    public static func locate(chunk: [String], visibleIndex: Int) -> Located? {
        let all = locateAll(chunk: chunk)
        return all.indices.contains(visibleIndex) ? all[visibleIndex] : nil
    }

    /// Every rendered diff line's file line in one pass, aligned with ``visibleLines(in:)``: the
    /// new file's line for an added or context line, the old file's for a removed one, nil for a
    /// hunk header, a binary note or a "\ No newline" marker. What a diff view numbers its
    /// lines with.
    public static func locateAll(chunk: [String]) -> [Located?] {
        var out: [Located?] = []
        var old = 0, new = 0, inHunk = false
        for raw in chunk {
            if raw.hasPrefix("@@") {
                // @@ -a,b +c,d @@ — counters start at a and c; the header itself has no line.
                let parts = raw.split(separator: " ")
                func start(_ token: Substring) -> Int { Int(token.dropFirst().split(separator: ",").first ?? "") ?? 1 }
                if parts.count >= 3 { old = start(parts[1]); new = start(parts[2]) }
                inHunk = true
                out.append(nil)
                continue
            }
            guard inHunk else {
                if raw.hasPrefix("Binary files") { out.append(nil) }
                continue
            }
            if raw.hasPrefix("+") {
                out.append(Located(line: new, side: "+", text: String(raw.dropFirst())))
                new += 1
            } else if raw.hasPrefix("-") {
                out.append(Located(line: old, side: "-", text: String(raw.dropFirst())))
                old += 1
            } else if raw.hasPrefix("\\") || raw.hasPrefix("Binary files") {
                out.append(nil)
            } else {
                out.append(Located(line: new, side: " ", text: raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw))
                old += 1
                new += 1
            }
        }
        return out
    }
}

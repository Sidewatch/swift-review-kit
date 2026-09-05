//
//  DiffLineLocator.swift
//  ReviewKit
//
//  Maps a rendered unified-diff line back to a file line, so a click on the Nth visible line of
//  a chunk can say "src/main.py:7, added".
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

/// Maps a rendered unified-diff line back to a file line, so a click on the Nth visible line
/// of a chunk can say "src/main.py:7, added".
public enum DiffLineLocator {
    /// A located diff line: where it lives in the file and what it says.
    public struct Located: Equatable, Sendable {
        public let line: Int
        public let side: String
        public let text: String
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
        let visible = visibleLines(in: chunk)
        guard visible.indices.contains(visibleIndex) else { return nil }
        let targetChunkIndex = visible[visibleIndex].index
        var old = 0, new = 0
        for (i, raw) in chunk.enumerated() {
            if raw.hasPrefix("@@") {
                // @@ -a,b +c,d @@ — counters start at a and c; the header itself has no line.
                let parts = raw.split(separator: " ")
                func start(_ token: Substring) -> Int { Int(token.dropFirst().split(separator: ",").first ?? "") ?? 1 }
                if parts.count >= 3 { old = start(parts[1]); new = start(parts[2]) }
                if i == targetChunkIndex { return nil }
                continue
            }
            if i == targetChunkIndex {
                if raw.hasPrefix("+") { return Located(line: new, side: "+", text: String(raw.dropFirst())) }
                if raw.hasPrefix("-") { return Located(line: old, side: "-", text: String(raw.dropFirst())) }
                if raw.hasPrefix("\\") || raw.hasPrefix("Binary files") { return nil }
                return Located(line: new, side: " ", text: raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw)
            }
            if raw.hasPrefix("+") { new += 1 }
            else if raw.hasPrefix("-") { old += 1 }
            else if raw.hasPrefix("\\") { }
            else if i > 0 { old += 1; new += 1 }   // context (only meaningful inside a hunk)
        }
        return nil
    }
}

//
//  RegexMatches.swift
//  ChangeFacts
//
//  Every match of a pattern as its capture groups, the one regex idiom the readers share.
//
//  Created by David Sherlock on 9/22/26.
//

import Foundation

/// Every match of a pattern in a text, each as its capture groups as strings.
///
/// Index 0 is the whole match; a group that did not participate is `""`, never a crash. An
/// invalid pattern matches nothing. The texts are single files or a tool's output, not
/// corpora, so patterns are compiled per call.
enum RegexMatches {

    /// All matches of `pattern` in `text`, in order.
    static func all(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }

    /// The first match of `pattern` in `text`, or `nil`.
    static func first(_ pattern: String, in text: String) -> [String]? { all(pattern, in: text).first }

    /// The last match of `pattern` in `text`, or `nil` — where a runner's summary line sits.
    static func last(_ pattern: String, in text: String) -> [String]? { all(pattern, in: text).last }
}

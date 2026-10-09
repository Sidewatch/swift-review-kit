//
//  ReviewMarkRecords.swift
//  ReviewKit
//
//  The property-list shape the reviewed marks are stored in, and the conversion both ways.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The reviewed marks as `UserDefaults` stores them: repo key → path → stamp, with an empty
/// string standing for a mark without a stamp (a property list cannot hold nil, and a blob
/// hash is never empty). The shape replaced an earlier repo key → [path] list before launch,
/// so nothing migrates it: the old value fails the read and the marks start empty.
enum ReviewMarkRecords {

    /// The stored form of `marks`.
    static func encode(_ marks: [String: [String: ReviewMark]]) -> [String: [String: String]] {
        marks.mapValues { $0.mapValues { $0.stamp ?? "" } }
    }

    /// The marks in `records`, or nil when the value is not in the stored shape.
    static func decode(_ records: Any?) -> [String: [String: ReviewMark]]? {
        guard let records = records as? [String: [String: String]] else { return nil }
        return records.mapValues { $0.mapValues { ReviewMark(stamp: $0.isEmpty ? nil : $0) } }
    }
}

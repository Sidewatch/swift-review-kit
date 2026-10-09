//
//  ReviewMark.swift
//  ReviewKit
//
//  One file's reviewed mark: reviewed as the content its stamp names.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One file's reviewed mark. The stamp names the content that was reviewed — the working-tree
/// blob hash the host computes — so an edit after the review, which changes the stamp, leaves
/// the mark behind. A mark without a stamp was made by a host that does not stamp.
struct ReviewMark: Equatable, Sendable {

    /// The content stamp the mark was made against, nil for an unstamped mark.
    let stamp: String?
}

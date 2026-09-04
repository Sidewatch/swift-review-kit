import Foundation

/// The one message an agent receives for a batch of ``DiffReviewComment``s.
public enum DiffReviewMessage {
    /// Numbered, one file:line reference per comment, the quoted line for orientation, then
    /// the remark. Empty for no comments.
    public static func format(_ comments: [DiffReviewComment], repoName: String) -> String {
        guard !comments.isEmpty else { return "" }
        var out = "Review comments (\(comments.count)) on \(repoName) — please address each:\n"
        for (i, c) in comments.enumerated() {
            out += "\n\(i + 1). \(c.reference)"
            if !c.side.isEmpty { out += " (\(c.side == " " ? "context" : c.side == "+" ? "added" : "removed") line)" }
            if !c.quoted.isEmpty { out += "\n   `\(c.quoted.trimmingCharacters(in: .whitespaces))`" }
            out += "\n   → \(c.text)"
        }
        return out + "\n"
    }
}
